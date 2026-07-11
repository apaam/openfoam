#!/usr/bin/env bash
# Resolve native OpenFOAM install prefix and etc/bashrc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REWRITE_MARKER=".prefix-rewritten"

_openfoam_python() {
  printf '%s' "${OPENFOAM_PYTHON:-python3}"
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
  local script old new

  [[ -f "${rewritten}" ]] && return 0
  if [[ -f "${marker}" ]]; then
    script="$(rewrite_script_path)" || true
    if [[ -n "${script:-}" ]]; then
      old="$(<"${marker}")"
      new="$(cd "${prefix}" && pwd)"
      if [[ -n "${old}" && "${old}" != "${new}" ]]; then
        bash "${script}" "${prefix}" "${old}" "${new}"
      fi
    fi
  fi
  printf '%s\n' "$(cd "${prefix}" && pwd)" >"${rewritten}"
}

resolve_openfoam_prefix() {
  local pkg_dir py prefix cli_root

  if [[ -n "${OPENFOAM_PREFIX:-}" && -f "${OPENFOAM_PREFIX}/etc/bashrc" ]]; then
    prefix="$(cd "${OPENFOAM_PREFIX}" && pwd)"
    rewrite_installed_prefix "${prefix}"
    printf '%s' "${prefix}"
    return 0
  fi

  pkg_dir="${SCRIPT_DIR}"
  if [[ "${pkg_dir}" == */share/openfoam/cli ]]; then
    cli_root="$(cd "${pkg_dir}/../../.." && pwd)"
    if [[ -f "${cli_root}/.openfoam-prefix" ]]; then
      prefix="$(<"${cli_root}/.openfoam-prefix")"
      prefix="$(cd "${prefix}" && pwd)"
      rewrite_installed_prefix "${prefix}"
      printf '%s' "${prefix}"
      return 0
    fi
    if [[ -f "${cli_root}/etc/bashrc" ]]; then
      prefix="$(cd "${cli_root}" && pwd)"
      rewrite_installed_prefix "${prefix}"
      printf '%s' "${prefix}"
      return 0
    fi
  fi

  py="$(_openfoam_python)"

  if [[ -f "${pkg_dir}/prefix/etc/bashrc" ]]; then
    "${py}" -m openfoam.prefix
    return 0
  fi

  "${py}" -m openfoam.prefix
}

require_native_prefix() {
  if ! OPENFOAM_PREFIX="$(resolve_openfoam_prefix)"; then
    cat >&2 <<EOF
Native OpenFOAM install not found.

Install from wheel:  pip install openfoam-*.whl   (make wheel / wheel-dist)
Or extract cpack:    tar xzf openfoam-native-*.tar.gz -C <prefix>
                     eval "\$(<prefix>/bin/openfoam env-path)"
Or build locally:    source build/openfoam/etc/bashrc
                     export PATH="build/cli/bin:\$PATH"
EOF
    exit 1
  fi
  export OPENFOAM_PREFIX
  OPENFOAM_BASHRC="${OPENFOAM_PREFIX}/etc/bashrc"
  export OPENFOAM_BASHRC
}
