#!/usr/bin/env bash
set -euo pipefail

ROOT="/build/openfoam"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"

abs_under_root() {
  openfoam_abs_under_root "${ROOT}" "$1"
}

openfoam_apply_build_path_defaults
export OPENFOAM_ROOT="${ROOT}"
export OPENFOAM_BUILD="$(abs_under_root "${OPENFOAM_BUILD:?OPENFOAM_BUILD required}")"
OPENFOAM_STAGE="$(abs_under_root "${OPENFOAM_STAGE:?OPENFOAM_STAGE required}")"
case "${OPENFOAM_BUILD}" in
*docker-build*) ;;
*)
  echo "[bake_openfoam] ERROR: expected OPENFOAM_BUILD=build/docker-build (got ${OPENFOAM_BUILD})" >&2
  exit 1
  ;;
esac
export OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
export NUM_JOBS="${NUM_JOBS:-$(nproc)}"
export PLATFORM=linux

bash "${ROOT}/scripts/build_openfoam.sh"
bash "${SCRIPT_DIR}/stage_openfoam.sh" "${OPENFOAM_BUILD}" "${OPENFOAM_STAGE}"
bash "${SCRIPT_DIR}/resolve_runtime_apt.sh" \
  "${OPENFOAM_STAGE}" "${OPENFOAM_STAGE}/runtime-apt.txt"
