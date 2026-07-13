#!/usr/bin/env bash
set -euo pipefail

# Runtime image: load OpenFOAM via /root/.bashrc (or OF bashrc + bundled PATH).

OPENFOAM_PREFIX="${OPENFOAM_PREFIX:-/opt/openfoam}"
export OPENFOAM_PREFIX
export OPENFOAM_BASHRC="${OPENFOAM_BASHRC:-${OPENFOAM_PREFIX}/etc/bashrc}"
export HOME="${HOME:-/root}"

# OpenFOAM etc/bashrc references optional unset vars (fails under set -u).
source_openfoam_env() {
  local rc="$1"
  local had_e=0 had_u=0
  case "$-" in *e*) had_e=1; set +e ;; esac
  case "$-" in *u*) had_u=1; set +u ;; esac
  # shellcheck disable=SC1090
  source "${rc}"
  [[ "${had_u}" -eq 1 ]] && set -u
  [[ "${had_e}" -eq 1 ]] && set -e
}

if [[ -f "${HOME}/.bashrc" ]]; then
  source_openfoam_env "${HOME}/.bashrc"
elif [[ -f "${OPENFOAM_BASHRC}" ]]; then
  source_openfoam_env "${OPENFOAM_BASHRC}"
  if [[ -d "${OPENFOAM_PREFIX}/lib/bundled/mpi-bin" ]]; then
    case ":${PATH}:" in
    *":${OPENFOAM_PREFIX}/lib/bundled/mpi-bin:"*) ;;
    *) export PATH="${OPENFOAM_PREFIX}/lib/bundled/mpi-bin${PATH:+:$PATH}" ;;
    esac
  fi
else
  echo "Missing ${HOME}/.bashrc and ${OPENFOAM_BASHRC}" >&2
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  exec bash
fi

exec "$@"
