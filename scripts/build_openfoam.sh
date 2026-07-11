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

  # shellcheck source=scripts/openfoam_install_excludes.sh
  source "${OPENFOAM_ROOT}/scripts/openfoam_install_excludes.sh"

  echo "[build_openfoam] Refreshing cache (${CACHE_BUILD}/)"
  mkdir -p "${CACHE_BUILD}"
  rsync -a "${OPENFOAM_INSTALL_EXCLUDES[@]}" \
    "${OPENFOAM_BUILD}/" "${CACHE_BUILD}/"
}

sync_source() {
  mkdir -p "${OPENFOAM_BUILD}"
  rsync -ura "${OPENFOAM_SOURCE}/" "${OPENFOAM_BUILD}/"
}

setup_platform_deps() {
  case "${PLATFORM}" in
    darwin)
      rsync -u "${OPENFOAM_ROOT}/Brewfile" "${OPENFOAM_BUILD}/Brewfile"
      rsync -u "${OPENFOAM_ROOT}/configure.sh" "${OPENFOAM_BUILD}/configure.sh"
      cd "${OPENFOAM_BUILD}"
      brew bundle -f
      brew bundle check --verbose --no-upgrade
      if [[ -f Brewfile.lock.json ]]; then
        cat Brewfile.lock.json
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
  if [[ "${OPENFOAM_BUILD_MODULES}" =~ ^(0|false|no|off)$ ]]; then
    allwmake_extra=(-prefix=none)
    echo "[build_openfoam] Skipping modules/plugins (core OpenFOAM only)"
  fi

  # OpenFOAM bashrc uses optional unset vars and functions that return 1.
  set +eu
  export SHELL=/bin/bash
  source etc/bashrc
  foamSystemCheck
  ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s -q -k
  ./Allwmake -j "${NUM_JOBS}" "${allwmake_extra[@]}" -s
  set -eu
}

resolve_platform
cd "${OPENFOAM_ROOT}"
seed_cache

if [[ -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[build_openfoam] Incremental build ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
else
  echo "[build_openfoam] Full build OpenFOAM ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
fi

sync_source
setup_platform_deps
compile_openfoam
refresh_cache

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[build_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

echo "[build_openfoam] OpenFOAM install ready at ${OPENFOAM_BUILD}"
