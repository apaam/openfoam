#!/usr/bin/env bash
# Resolve native OpenFOAM install prefix and etc/bashrc.

_openfoam_python() {
  printf '%s' "${OPENFOAM_PYTHON:-python3}"
}

resolve_openfoam_prefix() {
  if [[ -n "${OPENFOAM_PREFIX:-}" && -f "${OPENFOAM_PREFIX}/etc/bashrc" ]]; then
    printf '%s' "$(cd "${OPENFOAM_PREFIX}" && pwd)"
    return 0
  fi

  local pkg_dir repo_root py
  pkg_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${pkg_dir}/../.." && pwd)"
  py="$(_openfoam_python)"

  if [[ -f "${repo_root}/build/openfoam/etc/bashrc" ]]; then
    printf '%s' "$(cd "${repo_root}/build/openfoam" && pwd)"
    return 0
  fi

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

Install from wheel:  pip install openfoam-*.whl   (make wheel-dist)
Or extract cpack:    make cpack-dist
Or build locally:    make install

Set OPENFOAM_PREFIX to an install tree with etc/bashrc.
EOF
    exit 1
  fi
  export OPENFOAM_PREFIX
  OPENFOAM_BASHRC="${OPENFOAM_PREFIX}/etc/bashrc"
  export OPENFOAM_BASHRC
}
