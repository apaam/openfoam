#!/usr/bin/env bash
# Prepare install tree for wheel/cpack (same staging as docker/bake_openfoam.sh).
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

export FORCE_STAGE
bash "${ROOT}/docker/stage_openfoam.sh" "${OPENFOAM_BUILD}" "${OPENFOAM_STAGE}"

OLD_PREFIX="$(cd "${OPENFOAM_BUILD}" && pwd)"
NEW_PREFIX="$(cd "${OPENFOAM_STAGE}" && pwd)"
bash "${ROOT}/docker/rewrite_openfoam_paths.sh" \
  "${NEW_PREFIX}" "${OLD_PREFIX}" "${NEW_PREFIX}"

printf '%s\n' "${NEW_PREFIX}" > "${NEW_PREFIX}/.pack-source-prefix"
echo "[prepare_openfoam_pack_tree] Ready at ${NEW_PREFIX}"
