#!/usr/bin/env bash
set -euo pipefail

# Runtime image: load OpenFOAM via /root/.bashrc (or OF bashrc + bundled PATH).

OPENFOAM_PREFIX="${OPENFOAM_PREFIX:-/opt/openfoam}"
export OPENFOAM_PREFIX
export OPENFOAM_BASHRC="${OPENFOAM_BASHRC:-${OPENFOAM_PREFIX}/etc/bashrc}"
export HOME="${HOME:-/root}"

if [[ -f "${HOME}/.bashrc" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.bashrc"
elif [[ -f "${OPENFOAM_BASHRC}" ]]; then
  # shellcheck disable=SC1090
  source "${OPENFOAM_BASHRC}"
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
