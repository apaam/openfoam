#!/usr/bin/env bash
# Resolve native OpenFOAM install prefix and etc/bashrc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REWRITE_MARKER=".prefix-rewritten"
DEFAULT_OPENFOAM_PREFIX="/opt/openfoam"

_openfoam_python() {
  printf '%s' "${OPENFOAM_PYTHON:-python3}"
}

normalize_prefix_path() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    (cd "${path}" && pwd)
    return 0
  fi
  if command -v realpath >/dev/null 2>&1 && realpath -m "${path}" >/dev/null 2>&1; then
    realpath -m "${path}"
    return 0
  fi
  "$(_openfoam_python)" -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${path}"
}

rewrite_script_path() {
  local script="${SCRIPT_DIR}/rewrite_openfoam_paths.sh"
  [[ -f "${script}" ]] || return 1
  printf '%s' "${script}"
}

rewrite_installed_prefix() {
  local prefix="$1"
  local marker="${prefix}/.pack-source-prefix"
  local rewritten="${prefix}/${REWRITE_MARKER}"
  local script old new of_tree

  [[ -d "${prefix}" ]] || return 0
  [[ -f "${rewritten}" ]] && return 0
  if [[ -f "${marker}" ]]; then
    script="$(rewrite_script_path)" || true
    if [[ -n "${script:-}" ]]; then
      old="$(<"${marker}")"
      new="$(cd "${prefix}" && pwd)"
      of_tree="${prefix}/openfoam"
      if [[ -n "${old}" && "${old}" != "${new}" ]]; then
        if [[ -f "${of_tree}/etc/bashrc" ]]; then
          bash "${script}" "${of_tree}" "${old}" "${new}"
        else
          bash "${script}" "${prefix}" "${old}" "${new}"
        fi
      fi
    fi
  fi
  printf '%s\n' "$(cd "${prefix}" && pwd)" >"${rewritten}"
}

resolve_local_build_prefix() {
  local pkg_dir="$1"
  local cli_root

  [[ "${pkg_dir}" == */share/openfoam/cli ]] || return 1
  cli_root="$(cd "${pkg_dir}/../../.." && pwd)"
  # Product pack: CLI root has etc/bashrc + openfoam/.
  if [[ -f "${cli_root}/etc/bashrc" ]]; then
    normalize_prefix_path "${cli_root}"
    return 0
  fi
  return 1
}

resolve_runtime_prefix() {
  local prefix=""

  if [[ -n "${OPENFOAM_PREFIX:-}" ]]; then
    normalize_prefix_path "${OPENFOAM_PREFIX}"
    return 0
  fi

  if prefix="$(resolve_local_build_prefix "${SCRIPT_DIR}")"; then
    printf '%s' "${prefix}"
    return 0
  fi

  printf '%s' "${DEFAULT_OPENFOAM_PREFIX}"
}

prefix_has_bashrc() {
  local root="$1"
  # Product layout: wrapper + upstream under openfoam/.
  if [[ -f "${root}/etc/bashrc" && -f "${root}/openfoam/etc/bashrc" ]]; then
    return 0
  fi
  # Local openfoam-build (flat).
  if [[ -f "${root}/etc/bashrc" && ! -d "${root}/openfoam" ]]; then
    return 0
  fi
  return 1
}

prefix_hint_missing_bashrc() {
  local prefix="$1"
  cat >&2 <<EOF
Note: ${prefix}/etc/bashrc not found.
Pack:    tar xzf openfoam-native-*.tar.gz -C <prefix>
Local:   make openfoam && source ${OPENFOAM_BUILD:-${BUILD_ROOT:-build}/openfoam-build}/etc/bashrc
         (docker-shell uses BUILD_ROOT=docker-build)
Set OPENFOAM_PREFIX to your install root (default: ${DEFAULT_OPENFOAM_PREFIX}).
EOF
}

resolve_openfoam_prefix() {
  local prefix=""

  prefix="$(resolve_runtime_prefix)"
  if prefix_has_bashrc "${prefix}"; then
    rewrite_installed_prefix "${prefix}"
    printf '%s' "${prefix}"
    return 0
  fi
  return 1
}

require_native_prefix() {
  local prefix=""

  if ! prefix="$(resolve_openfoam_prefix)"; then
    prefix="$(resolve_runtime_prefix)"
    cat >&2 <<EOF
OpenFOAM install not found at ${prefix}.

Pack:    tar xzf openfoam-native-*.tar.gz -C <prefix>
Local:   make all && source ${OPENFOAM_BUILD:-${BUILD_ROOT:-build}/openfoam-build}/etc/bashrc
         (docker-shell uses BUILD_ROOT=docker-build)
Set OPENFOAM_PREFIX to your install root (default: ${DEFAULT_OPENFOAM_PREFIX}).
EOF
    exit 1
  fi
  export OPENFOAM_PREFIX="${prefix}"
  OPENFOAM_BASHRC="${OPENFOAM_PREFIX}/etc/bashrc"
  export OPENFOAM_BASHRC
}
