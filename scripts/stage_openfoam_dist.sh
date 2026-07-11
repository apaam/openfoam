#!/usr/bin/env bash
# Stage build/ for distribution: sync, rewrite paths, bundle runtime, fix prefs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
load_make_config "${ROOT}"

OPENFOAM_BUILD="${OPENFOAM_BUILD:-${ROOT}/build}"
OPENFOAM_STAGE="${OPENFOAM_STAGE:-${ROOT}/build/stage/openfoam}"
FORCE_STAGE="${FORCE_STAGE:-0}"

case "${OPENFOAM_BUILD}" in
/*) ;;
*) OPENFOAM_BUILD="${ROOT}/${OPENFOAM_BUILD}" ;;
esac
case "${OPENFOAM_STAGE}" in
/*) ;;
*) OPENFOAM_STAGE="${ROOT}/${OPENFOAM_STAGE}" ;;
esac

bash "${ROOT}/docker/stage_openfoam.sh" "${OPENFOAM_BUILD}" "${OPENFOAM_STAGE}"

OLD_PREFIX="$(cd "${OPENFOAM_BUILD}" && pwd)"
NEW_PREFIX="$(cd "${OPENFOAM_STAGE}" && pwd)"
bash "${ROOT}/docker/rewrite_openfoam_paths.sh" \
  "${OPENFOAM_STAGE}" "${OLD_PREFIX}" "${NEW_PREFIX}"

bash "${ROOT}/scripts/bundle_openfoam_runtime.sh" "${OPENFOAM_STAGE}"
bash "${ROOT}/scripts/rewrite_openfoam_prefs.sh" "${OPENFOAM_STAGE}"

date -u +%Y-%m-%dT%H:%M:%SZ > "${OPENFOAM_STAGE}/.dist-stamp"
echo "[stage_openfoam_dist] Ready at ${OPENFOAM_STAGE}"
