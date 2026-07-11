#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_ROOT="${OPENFOAM_ROOT:-$(pwd)}"
OPENFOAM_SOURCE="${OPENFOAM_SOURCE:-${OPENFOAM_ROOT}/openfoam-source}"
OPENFOAM_BUILD="${OPENFOAM_BUILD:-${OPENFOAM_ROOT}/build}"
CACHE_BUILD="${CACHE_BUILD:-}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
NUM_JOBS="${NUM_JOBS:-2}"
PLATFORM="${PLATFORM:-auto}"
OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES:-0}"
OPENFOAM_SYSTEM_CHECK="${OPENFOAM_SYSTEM_CHECK:-auto}"
OPENFOAM_SKIP_ALLWMAKE="${OPENFOAM_SKIP_ALLWMAKE:-auto}"

if [[ -f "${OPENFOAM_ROOT}/scripts/load_make_config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${OPENFOAM_ROOT}/scripts/load_make_config.sh"
  load_make_config "${OPENFOAM_ROOT}"
fi

abs_under_root() {
  local path="$1"
  case "${path}" in
  /*) printf '%s' "${path}" ;;
  *) printf '%s' "${OPENFOAM_ROOT}/${path}" ;;
  esac
}

OPENFOAM_ROOT="$(cd "${OPENFOAM_ROOT}" && pwd)"
OPENFOAM_BUILD="$(abs_under_root "${OPENFOAM_BUILD}")"
OPENFOAM_SOURCE="$(abs_under_root "${OPENFOAM_SOURCE:-openfoam-source}")"
BUILD_STAMP="${OPENFOAM_BUILD}/.openfoam-build-stamp"

# shellcheck source=scripts/openfoam_install_excludes.sh
source "${OPENFOAM_ROOT}/scripts/openfoam_install_excludes.sh"
# shellcheck source=scripts/platform_paths.sh
source "${OPENFOAM_ROOT}/scripts/platform_paths.sh"

is_incremental_build() {
  [[ -d "${OPENFOAM_BUILD}/platforms" && -f "${OPENFOAM_BUILD}/etc/bashrc" ]]
}

source_tree_id() {
  if git -C "${OPENFOAM_SOURCE}" rev-parse --is-inside-work-tree &>/dev/null; then
    local head diff_hash
    head=$(git -C "${OPENFOAM_SOURCE}" rev-parse HEAD)
    diff_hash=$(
      {
        git -C "${OPENFOAM_SOURCE}" diff HEAD
        git -C "${OPENFOAM_SOURCE}" diff --cached HEAD
        git -C "${OPENFOAM_SOURCE}" ls-files --others --exclude-standard
      } | {
        if command -v shasum >/dev/null; then shasum; else sha256sum; fi
      } | awk '{print $1}'
    )
    printf 'git:%s:%s' "${head}" "${diff_hash}"
  else
    local newest=
    newest=$(
      find "${OPENFOAM_SOURCE}" -type f -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null \
        | head -1 || true
    )
    if [[ -n "${newest}" && -f "${newest}" ]]; then
      printf 'file:%s:%s' "${newest}" "${newest}"
    else
      printf 'file::'
    fi
  fi
}

build_config_id() {
  printf '%s:%s' "${PLATFORM}" "${OPENFOAM_BUILD_MODULES}"
}

rsync_would_change() {
  rsync -ura --dry-run --itemize-changes \
    "${OPENFOAM_SOURCE_SYNC_EXCLUDES[@]}" \
    "${OPENFOAM_SOURCE}/" "${OPENFOAM_BUILD}/" \
    | grep -qE '^[><ch][fdLDS\.]'
}

platform_config_changed() {
  case "${PLATFORM}" in
  darwin)
    [[ -f "${OPENFOAM_BUILD}/etc/prefs.sh" ]] || return 0
    [[ "${OPENFOAM_ROOT}/Brewfile" -nt "${OPENFOAM_BUILD}/etc/prefs.sh" ]] && return 0
    [[ "${OPENFOAM_ROOT}/configure.sh" -nt "${OPENFOAM_BUILD}/etc/prefs.sh" ]] && return 0
    ;;
  esac
  return 1
}

should_skip_allwmake() {
  case "${OPENFOAM_SKIP_ALLWMAKE}" in
  0 | no | false | off) return 1 ;;
  esac
  if [[ "${OPENFOAM_FORCE_REBUILD:-${FORCE:-0}}" =~ ^(1|yes|true|on)$ ]]; then
    return 1
  fi
  is_incremental_build || return 1
  [[ -f "${BUILD_STAMP}" ]] || return 1

  local saved_source saved_config
  saved_source=$(sed -n '1p' "${BUILD_STAMP}")
  saved_config=$(sed -n '2p' "${BUILD_STAMP}")
  [[ -n "${saved_source}" && -n "${saved_config}" ]] || return 1
  [[ "${saved_source}" == "$(source_tree_id)" ]] || return 1
  [[ "${saved_config}" == "$(build_config_id)" ]] || return 1
  rsync_would_change && return 1
  platform_config_changed && return 1
  return 0
}

write_build_stamp() {
  printf '%s\n%s\n' "$(source_tree_id)" "$(build_config_id)" >"${BUILD_STAMP}"
}

should_run_system_check() {
  case "${OPENFOAM_SYSTEM_CHECK}" in
  1 | yes | true | on) return 0 ;;
  0 | no | false | off) return 1 ;;
  auto | "")
    if is_incremental_build; then
      return 1
    fi
    return 0
    ;;
  *)
    echo "[build_openfoam] Unknown OPENFOAM_SYSTEM_CHECK=${OPENFOAM_SYSTEM_CHECK}" >&2
    return 1
    ;;
  esac
}

resolve_platform() {
  if [[ "${PLATFORM}" != "auto" ]]; then
    return
  fi
  if [[ "${OSTYPE}" == "darwin"* ]]; then
    PLATFORM=darwin
  elif [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    PLATFORM=linux
  else
    echo "[build_openfoam] Unsupported OSTYPE: ${OSTYPE}" >&2
    exit 1
  fi
}

seed_cache() {
  [[ -n "${CACHE_BUILD}" ]] || return 0
  [[ -d "${OPENFOAM_BUILD}/etc" ]] && return 0
  [[ -d "${CACHE_BUILD}/etc" ]] || return 0

  echo "[build_openfoam] Seeding build/ from cache -> ${OPENFOAM_BUILD}"
  mkdir -p "${OPENFOAM_BUILD}"
  rsync -a "${CACHE_BUILD}/" "${OPENFOAM_BUILD}/"
}

refresh_cache() {
  [[ -n "${CACHE_BUILD}" ]] || return 0
  [[ -d "${OPENFOAM_BUILD}/etc" ]] || return 0

  echo "[build_openfoam] Refreshing cache (${CACHE_BUILD}/)"
  mkdir -p "${CACHE_BUILD}"
  rsync -a "${OPENFOAM_INSTALL_EXCLUDES[@]}" \
    "${OPENFOAM_BUILD}/" "${CACHE_BUILD}/"
}

sync_source() {
  mkdir -p "${OPENFOAM_BUILD}"
  rsync -ura --delete-excluded \
    "${OPENFOAM_SOURCE_SYNC_EXCLUDES[@]}" \
    "${OPENFOAM_SOURCE}/" "${OPENFOAM_BUILD}/"
}

setup_platform_deps() {
  case "${PLATFORM}" in
    darwin)
      rsync -u "${OPENFOAM_ROOT}/Brewfile" "${OPENFOAM_BUILD}/Brewfile"
      rsync -u "${OPENFOAM_ROOT}/configure.sh" "${OPENFOAM_BUILD}/configure.sh"
      cd "${OPENFOAM_BUILD}"
      local need_brew=false
      if ! is_incremental_build; then
        need_brew=true
      elif [[ "${OPENFOAM_ROOT}/Brewfile" -nt etc/prefs.sh ]] \
        || [[ "${OPENFOAM_ROOT}/configure.sh" -nt etc/prefs.sh ]] \
        || [[ ! -f etc/prefs.sh ]]; then
        need_brew=true
      fi
      if [[ "${need_brew}" == true ]]; then
        brew bundle -f
        brew bundle check --verbose --no-upgrade
        if [[ -f Brewfile.lock.json ]]; then
          cat Brewfile.lock.json
        fi
      else
        echo "[build_openfoam] Skipping brew bundle (incremental, Brewfile unchanged)"
      fi
      if [[ ! -f etc/prefs.sh ]] \
        || [[ "${OPENFOAM_ROOT}/Brewfile" -nt etc/prefs.sh ]] \
        || [[ "${OPENFOAM_ROOT}/configure.sh" -nt etc/prefs.sh ]]; then
        bash -ex configure.sh
      else
        echo "[build_openfoam] Skipping configure.sh (prefs up to date)"
      fi
      ;;
    linux)
      cd "${OPENFOAM_BUILD}"
      ;;
    *)
      echo "[build_openfoam] Unsupported PLATFORM: ${PLATFORM}" >&2
      exit 1
      ;;
  esac
}

compile_openfoam() {
  local -a allwmake_extra=()
  local incremental=false
  if is_incremental_build; then
    incremental=true
  fi
  if [[ "${OPENFOAM_BUILD_MODULES}" =~ ^(0|false|no|off)$ ]]; then
    allwmake_extra=(-prefix=none)
    echo "[build_openfoam] Skipping modules/plugins (core OpenFOAM only)"
  fi

  # OpenFOAM bashrc uses optional unset vars and functions that return 1.
  set +eu
  source etc/bashrc
  export SHELL="$(platform_paths_resolve_bash)"

  if should_run_system_check; then
    foamSystemCheck
  else
    echo "[build_openfoam] Skipping foamSystemCheck (OPENFOAM_SYSTEM_CHECK=${OPENFOAM_SYSTEM_CHECK})"
  fi

  if [[ "${incremental}" == true ]]; then
    echo "[build_openfoam] Incremental Allwmake (-s only)"
    ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s
  else
    echo "[build_openfoam] Full Allwmake (bootstrap + finalize)"
    ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s -q -k
    ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s
  fi
  set -eu
}

resolve_platform
cd "${OPENFOAM_ROOT}"
seed_cache

if is_incremental_build; then
  echo "[build_openfoam] Incremental build ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
else
  echo "[build_openfoam] Full build OpenFOAM ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
fi

sync_source
setup_platform_deps
if should_skip_allwmake; then
  echo "[build_openfoam] Skipping Allwmake (source and config unchanged)"
else
  compile_openfoam
  write_build_stamp
fi
refresh_cache

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[build_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

echo "[build_openfoam] OpenFOAM install ready at ${OPENFOAM_BUILD}"
