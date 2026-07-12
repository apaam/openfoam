#!/usr/bin/env bash
# Fallback build path defaults (tracked defaults: docs/make-config-default.mk).
# Call openfoam_apply_build_path_defaults after load_make_config.

openfoam_apply_build_path_defaults() {
  : "${OPENFOAM_BUILD:=build/openfoam-build}"
  : "${OPENFOAM_STAGE:=build/stage/openfoam-build}"
}

openfoam_abs_under_root() {
  local root="$1"
  local path="$2"
  case "${path}" in
  /*) printf '%s' "${path}" ;;
  *) printf '%s' "${root}/${path}" ;;
  esac
}

openfoam_load_build_paths() {
  local root="$1"
  if [[ -f "${root}/scripts/load_make_config.sh" ]]; then
    # shellcheck disable=SC1091
    source "${root}/scripts/load_make_config.sh"
    load_make_config "${root}"
  fi
  openfoam_apply_build_path_defaults
}

openfoam_expected_compiler() {
  case "$1" in
  darwin) printf 'Clang' ;;
  linux) printf 'Gcc' ;;
  *)
    echo "[build_openfoam] Unsupported PLATFORM for compiler: $1" >&2
    return 1
    ;;
  esac
}

openfoam_validate_build_dir() {
  local build_dir="$1"
  local platform="$2"
  local expected_compiler

  expected_compiler="$(openfoam_expected_compiler "${platform}")"

  if [[ "${platform}" != darwin && "${platform}" != linux ]]; then
    echo "[build_openfoam] ERROR: unsupported platform ${platform} (dir=${build_dir})" >&2
    exit 1
  fi

  local profile="${build_dir}/.phynexis-build-profile"
  if [[ -f "${profile}" ]]; then
    local saved_platform saved_compiler
    IFS=' ' read -r saved_platform saved_compiler _ < "${profile}"
    if [[ "${saved_platform}" != "${platform}" \
      || "${saved_compiler}" != "${expected_compiler}" ]]; then
      echo "[build_openfoam] ERROR: ${build_dir} profile is ${saved_platform}/${saved_compiler}," >&2
      echo "[build_openfoam]        but this run is ${platform}/${expected_compiler}." >&2
      echo "[build_openfoam]        Remove ${build_dir} or use the matching platform." >&2
      exit 1
    fi
  fi
}

openfoam_write_build_profile() {
  local build_dir="$1"
  local platform="$2"
  printf '%s %s\n' \
    "${platform}" \
    "$(openfoam_expected_compiler "${platform}")" \
    > "${build_dir}/.phynexis-build-profile"
}
