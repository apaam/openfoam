#!/usr/bin/env bash
# Stage build/ for distribution: sync, rewrite paths, bundle runtime, fix prefs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
load_make_config "${ROOT}"

OPENFOAM_STAGE="${OPENFOAM_STAGE:-${ROOT}/build/stage/openfoam}"
case "${OPENFOAM_STAGE}" in
/*) ;;
*) OPENFOAM_STAGE="${ROOT}/${OPENFOAM_STAGE}" ;;
esac

bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"

date -u +%Y-%m-%dT%H:%M:%SZ > "${OPENFOAM_STAGE}/.dist-stamp"
echo "[stage_openfoam_dist] Ready at ${OPENFOAM_STAGE}"
