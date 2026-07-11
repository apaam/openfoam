#!/usr/bin/env bash
# Resolve native OpenFOAM install prefix and etc/bashrc.

openfoam_cli_dir() {
  cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd
}

resolve_openfoam_prefix() {
  if [[ -n "${OPENFOAM_PREFIX:-}" && -f "${OPENFOAM_PREFIX}/etc/bashrc" ]]; then
    printf '%s' "$(cd "${OPENFOAM_PREFIX}" && pwd)"
    return 0
  fi

  local cli_dir repo_root
  cli_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${cli_dir}/../.." && pwd)"
  if [[ -f "${repo_root}/build/etc/bashrc" ]]; then
    printf '%s' "$(cd "${repo_root}/build" && pwd)"
    return 0
  fi

  if [[ -f "${cli_dir}/prefix/etc/bashrc" ]]; then
    printf '%s' "${cli_dir}/prefix"
    return 0
  fi

  if [[ -f "${cli_dir}/openfoam-native.tar.gz" ]]; then
    python3 -c 'from openfoam_cli.prefix import native_prefix; print(native_prefix())'
    return 0
  fi

  return 1
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
