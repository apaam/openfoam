#!/usr/bin/env bash
# Build path helpers (tracked defaults: docs/make-config-default.mk).
# openfoam_load_build_paths: load config, apply CONTAINER_BUILD remap, then defaults.
#
# BUILD_ROOT — active build tree; DOCKER_BUILD_ROOT when CONTAINER_BUILD=1.
# OPENFOAM_PREFIX — runtime install (CLI); not managed here.

openfoam_apply_build_path_defaults() {
  : "${BUILD_ROOT:=build}"
  : "${DOCKER_BUILD_ROOT:=docker-build}"
  : "${OPENFOAM_BUILD:=${BUILD_ROOT}/openfoam-build}"
  : "${OPENFOAM_STAGE:=${BUILD_ROOT}/stage/openfoam-build}"
  : "${OPENFOAM_CLI_BUILD:=${BUILD_ROOT}}"
  : "${BUILD_OPENFOAM_PACK_DIR:=${BUILD_ROOT}/openfoam-pack}"
  : "${DIST_NATIVE_DIR:=${BUILD_ROOT}/dist-native}"
  : "${DIST_DOCKER_DIR:=${BUILD_ROOT}/dist-docker}"
  : "${BUILD_DOCKER_DIR:=${BUILD_ROOT}/docker}"
  : "${BUILD_CLI_PACK_DIR:=${BUILD_ROOT}/cli-pack}"
  : "${BUILD_CLI_WHEEL_DIR:=${BUILD_ROOT}/cli-wheel}"
  : "${BUILD_CLI_BUILD_DIR:=${BUILD_ROOT}/cli-build}"
  : "${BUILD_CLI_WHEEL_STAGE_DIR:=${BUILD_ROOT}/stage/cli-wheel}"
}

# Match makefile CONTAINER_BUILD=1 remapping (docker-shell isolated tree).
openfoam_apply_container_build_paths() {
  case "${CONTAINER_BUILD:-}" in
  1) ;;
  *) return 0 ;;
  esac

  : "${DOCKER_BUILD_ROOT:=docker-build}"
  export BUILD_ROOT="${DOCKER_BUILD_ROOT}"
  export OPENFOAM_BUILD="${BUILD_ROOT}/openfoam-build"
  export OPENFOAM_CLI_BUILD="${BUILD_ROOT}"
  export OPENFOAM_STAGE="${BUILD_ROOT}/stage/openfoam-build"
  export BUILD_OPENFOAM_PACK_DIR="${BUILD_ROOT}/openfoam-pack"
  export DIST_NATIVE_DIR="${BUILD_ROOT}/dist-native"
  export DIST_DOCKER_DIR="${BUILD_ROOT}/dist-docker"
  export BUILD_DOCKER_DIR="${BUILD_ROOT}/docker"
  export BUILD_CLI_PACK_DIR="${BUILD_ROOT}/cli-pack"
  export BUILD_CLI_WHEEL_DIR="${BUILD_ROOT}/cli-wheel"
  export BUILD_CLI_BUILD_DIR="${BUILD_ROOT}/cli-build"
  export BUILD_CLI_WHEEL_STAGE_DIR="${BUILD_ROOT}/stage/cli-wheel"
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
  openfoam_apply_container_build_paths
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
