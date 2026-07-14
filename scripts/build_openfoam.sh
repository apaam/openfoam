#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_ROOT="${OPENFOAM_ROOT:-$(pwd)}"
OPENFOAM_SOURCE="${OPENFOAM_SOURCE:-openfoam-source}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
NUM_JOBS="${NUM_JOBS:-2}"
PLATFORM="${PLATFORM:-auto}"
OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES:-0}"
OPENFOAM_SYSTEM_CHECK="${OPENFOAM_SYSTEM_CHECK:-auto}"
OPENFOAM_SKIP_ALLWMAKE="${OPENFOAM_SKIP_ALLWMAKE:-auto}"

# shellcheck disable=SC1091
source "${OPENFOAM_ROOT}/scripts/openfoam_build_paths.sh"
openfoam_load_build_paths "${OPENFOAM_ROOT}"

OPENFOAM_ROOT="$(cd "${OPENFOAM_ROOT}" && pwd)"
OPENFOAM_BUILD="$(openfoam_abs_under_root "${OPENFOAM_ROOT}" "${OPENFOAM_BUILD}")"
OPENFOAM_SOURCE="$(openfoam_abs_under_root "${OPENFOAM_ROOT}" "${OPENFOAM_SOURCE}")"
BUILD_STAMP="${OPENFOAM_BUILD}/.openfoam-build-stamp"

# shellcheck source=scripts/openfoam_install_paths.sh
source "${OPENFOAM_ROOT}/scripts/openfoam_install_paths.sh"
# shellcheck source=scripts/platform_paths.sh
source "${OPENFOAM_ROOT}/scripts/platform_paths.sh"
# shellcheck source=scripts/openfoam_build_meta.sh
source "${OPENFOAM_ROOT}/scripts/openfoam_build_meta.sh"

is_incremental_build() {
  [[ -d "${OPENFOAM_BUILD}/platforms" && -f "${OPENFOAM_BUILD}/etc/bashrc" ]]
}

openfoam_build_complete() {
  find "${OPENFOAM_BUILD}/platforms" -type f -path '*/bin/blockMesh' -print -quit 2>/dev/null \
    | grep -q .
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
  printf '%s:%s:%s' \
    "${PLATFORM}" \
    "$(openfoam_expected_compiler "${PLATFORM}")" \
    "${OPENFOAM_BUILD_MODULES}"
}

rsync_would_change() {
  rsync -ura --dry-run --itemize-changes \
    "${OPENFOAM_SOURCE_SYNC_EXCLUDES[@]}" \
    "${OPENFOAM_SOURCE}/" "${OPENFOAM_BUILD}/" \
    | grep -qE '^[><ch][fdLDS\.]'
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
  platform_config_changed "${OPENFOAM_ROOT}" "${OPENFOAM_BUILD}" "${PLATFORM}" && return 1
  openfoam_build_complete || return 1
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

sync_source() {
  mkdir -p "${OPENFOAM_BUILD}"
  # Do not use --delete-excluded: rsync 3.x treats it like --delete and would
  # remove compile artifacts (platforms/, wmake build/, stamps) and packaging
  # dirs that only exist under build/.
  rsync -ura \
    "${OPENFOAM_SOURCE_SYNC_EXCLUDES[@]}" \
    "${OPENFOAM_SOURCE}/" "${OPENFOAM_BUILD}/"
  if [[ "${OPENFOAM_BUILD_MODULES}" =~ ^(0|false|no|off)$ ]]; then
    rm -rf "${OPENFOAM_BUILD}/modules" "${OPENFOAM_BUILD}/plugins"
  fi
}

setup_platform_deps() {
  case "${PLATFORM}" in
    darwin)
      rsync -u "${OPENFOAM_ROOT}/Brewfile" "${OPENFOAM_BUILD}/Brewfile"
      rsync -u "${OPENFOAM_ROOT}/configure.sh" "${OPENFOAM_BUILD}/configure.sh"
      darwin_cleanup_foreign_platforms "${OPENFOAM_BUILD}"
      local need_brew=false
      if ! is_incremental_build; then
        need_brew=true
      elif darwin_need_configure "${OPENFOAM_ROOT}" "${OPENFOAM_BUILD}"; then
        need_brew=true
      fi
      if [[ "${need_brew}" == true ]]; then
        cd "${OPENFOAM_BUILD}"
        brew bundle -f
        brew bundle check --verbose --no-upgrade
        if [[ -f Brewfile.lock.json ]]; then
          cat Brewfile.lock.json
        fi
      else
        echo "[build_openfoam] Skipping brew bundle (incremental, Brewfile unchanged)"
      fi
      if darwin_need_configure "${OPENFOAM_ROOT}" "${OPENFOAM_BUILD}"; then
        cd "${OPENFOAM_BUILD}"
        bash -ex configure.sh
      else
        echo "[build_openfoam] Skipping configure.sh (prefs up to date)"
      fi
      ;;
    linux)
      linux_sync_etc_from_source "${OPENFOAM_SOURCE}" "${OPENFOAM_BUILD}"
      linux_cleanup_stale_platforms "${OPENFOAM_BUILD}"
      linux_write_prefs "${OPENFOAM_BUILD}"
      ;;
    *)
      echo "[build_openfoam] Unsupported PLATFORM: ${PLATFORM}" >&2
      exit 1
      ;;
  esac
}

compile_openfoam() {
  cd "${OPENFOAM_BUILD}"
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

  # Parent `make -jN` sets MAKEFLAGS with a jobserver that nested wmake cannot
  # inherit (recipe has no '+'). Drop it so Allwmake -j "${NUM_JOBS}" is honored.
  unset MAKEFLAGS MFLAGS

  local allwmake_status=0
  if [[ "${incremental}" == true ]]; then
    echo "[build_openfoam] Incremental Allwmake (-s only)"
    ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s || allwmake_status=$?
  else
    echo "[build_openfoam] Full Allwmake (bootstrap + finalize)"
    ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s -q -k || allwmake_status=$?
    if [[ "${allwmake_status}" -eq 0 ]]; then
      ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s || allwmake_status=$?
    fi
  fi
  set -eu
  if [[ "${allwmake_status}" -ne 0 ]]; then
    echo "[build_openfoam] Allwmake failed (exit ${allwmake_status})" >&2
    exit "${allwmake_status}"
  fi
}

resolve_platform
cd "${OPENFOAM_ROOT}"

openfoam_validate_build_dir "${OPENFOAM_BUILD}" "${PLATFORM}"
compiler="$(openfoam_expected_compiler "${PLATFORM}")"
echo "[build_openfoam] tree=${OPENFOAM_BUILD} platform=${PLATFORM} compiler=${compiler}"

if is_incremental_build; then
  echo "[build_openfoam] Incremental build ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
else
  echo "[build_openfoam] Full build OpenFOAM ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
fi

sync_source
setup_platform_deps
openfoam_write_build_profile "${OPENFOAM_BUILD}" "${PLATFORM}"
if should_skip_allwmake; then
  echo "[build_openfoam] Skipping Allwmake (source and config unchanged)"
else
  if [[ -f "${BUILD_STAMP}" ]] && ! openfoam_build_complete; then
    echo "[build_openfoam] Stale build stamp with incomplete install; resuming Allwmake"
    rm -f "${BUILD_STAMP}"
  fi
  compile_openfoam
  if openfoam_build_complete; then
    write_build_stamp
  else
    rm -f "${BUILD_STAMP}"
    echo "[build_openfoam] Build incomplete (blockMesh missing); re-run make to continue" >&2
    exit 1
  fi
fi

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[build_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

echo "[build_openfoam] OpenFOAM install ready at ${OPENFOAM_BUILD}"
