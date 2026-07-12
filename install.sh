#!/usr/bin/env bash
# Native macOS build entry. Linux hosts should use: make docker-build
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPENFOAM_ROOT="${OPENFOAM_ROOT:-${ROOT}}"
export OPENFOAM_VERSION="${1:-${OPENFOAM_VERSION:-v2412}}"

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
openfoam_load_build_paths "${ROOT}"

case "${OPENFOAM_BUILD##*/}" in
docker-build)
  echo "[install] ERROR: native install must use build/openfoam-build (got ${OPENFOAM_BUILD})" >&2
  echo "[install]        On Linux, use: make docker-build" >&2
  exit 1
  ;;
esac

bash "${ROOT}/scripts/build_openfoam.sh"
