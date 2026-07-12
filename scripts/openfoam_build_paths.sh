#!/usr/bin/env bash
# Build path helpers (tracked defaults: docs/make-config-default.mk).
# openfoam_load_build_paths: load config, apply CONTAINER_BUILD remap, then defaults.

openfoam_apply_build_path_defaults() {
  : "${OPENFOAM_BUILD:=build/openfoam-build}"
  : "${OPENFOAM_STAGE:=build/stage/openfoam-build}"
  : "${OPENFOAM_CLI_BUILD:=build}"
  : "${BUILD_OPENFOAM_PACK_DIR:=build/openfoam-pack}"
  : "${DIST_NATIVE_DIR:=build/dist-native}"
  : "${DIST_DOCKER_DIR:=build/dist-docker}"
  : "${BUILD_DOCKER_DIR:=build/docker}"
  : "${BUILD_CLI_PACK_DIR:=build/cli-pack}"
  : "${BUILD_CLI_WHEEL_DIR:=build/cli-wheel}"
  : "${BUILD_CLI_BUILD_DIR:=build/cli-build}"
  : "${BUILD_CLI_WHEEL_STAGE_DIR:=build/stage/cli-wheel}"
}

# Match makefile CONTAINER_BUILD=1 remapping (docker-shell isolated tree).
openfoam_apply_container_build_paths() {
  case "${CONTAINER_BUILD:-}" in
  1 | true | yes | on) ;;
  *) return 0 ;;
  esac

  : "${DOCKER_OPENFOAM_BUILD:=build/docker/openfoam-build}"
  : "${DOCKER_OPENFOAM_CLI_BUILD:=build/docker}"
  : "${DOCKER_OPENFOAM_STAGE:=build/docker/stage/openfoam-build}"
  : "${DOCKER_BUILD_OPENFOAM_PACK_DIR:=build/docker/openfoam-pack}"
  : "${DOCKER_DIST_NATIVE_DIR:=build/docker/dist-native}"
  : "${DOCKER_DIST_DOCKER_DIR:=build/docker/dist-docker}"
  : "${DOCKER_BUILD_DOCKER_DIR:=build/docker}"
  : "${DOCKER_BUILD_CLI_PACK_DIR:=build/docker/cli-pack}"
  : "${DOCKER_BUILD_CLI_WHEEL_DIR:=build/docker/cli-wheel}"
  : "${DOCKER_BUILD_CLI_BUILD_DIR:=build/docker/cli-build}"
  : "${DOCKER_BUILD_CLI_WHEEL_STAGE_DIR:=build/docker/stage/cli-wheel}"

  export OPENFOAM_BUILD="${DOCKER_OPENFOAM_BUILD}"
  export OPENFOAM_CLI_BUILD="${DOCKER_OPENFOAM_CLI_BUILD}"
  export OPENFOAM_STAGE="${DOCKER_OPENFOAM_STAGE}"
  export BUILD_OPENFOAM_PACK_DIR="${DOCKER_BUILD_OPENFOAM_PACK_DIR}"
  export DIST_NATIVE_DIR="${DOCKER_DIST_NATIVE_DIR}"
  export DIST_DOCKER_DIR="${DOCKER_DIST_DOCKER_DIR}"
  export BUILD_DOCKER_DIR="${DOCKER_BUILD_DOCKER_DIR}"
  export BUILD_CLI_PACK_DIR="${DOCKER_BUILD_CLI_PACK_DIR}"
  export BUILD_CLI_WHEEL_DIR="${DOCKER_BUILD_CLI_WHEEL_DIR}"
  export BUILD_CLI_BUILD_DIR="${DOCKER_BUILD_CLI_BUILD_DIR}"
  export BUILD_CLI_WHEEL_STAGE_DIR="${DOCKER_BUILD_CLI_WHEEL_STAGE_DIR}"
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
