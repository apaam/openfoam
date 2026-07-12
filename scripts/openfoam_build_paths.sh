#!/usr/bin/env bash
# Fallback build path defaults (tracked defaults: docs/make-config-default.mk).
# Call openfoam_apply_build_path_defaults after load_make_config.

openfoam_apply_build_path_defaults() {
  : "${OPENFOAM_BUILD:=build/host-build}"
  : "${OPENFOAM_STAGE:=build/stage/host-build}"
  : "${DOCKER_OPENFOAM_BUILD:=build/docker-build}"
  : "${DOCKER_OPENFOAM_STAGE:=build/stage/docker-build}"
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
