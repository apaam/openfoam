#!/usr/bin/env bash
# Prepare install tree for wheel/cpack (same staging as docker/bake_openfoam.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"

_bundle_override="${OPENFOAM_BUNDLE_RUNTIME+x}"
_saved_bundle="${OPENFOAM_BUNDLE_RUNTIME-}"
load_make_config "${ROOT}"
if [[ -n "${_bundle_override}" ]]; then
  export OPENFOAM_BUNDLE_RUNTIME="${_saved_bundle}"
else
  export OPENFOAM_BUNDLE_RUNTIME="${OPENFOAM_BUNDLE_RUNTIME:-0}"
fi

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

if [[ "${OPENFOAM_BUNDLE_RUNTIME}" =~ ^(1|yes|true|on)$ ]]; then
  bash "${ROOT}/scripts/bundle_openfoam_runtime.sh" "${NEW_PREFIX}"
  bash "${ROOT}/scripts/rewrite_openfoam_prefs.sh" "${NEW_PREFIX}"
else
  rm -rf "${NEW_PREFIX}/lib"
  echo "[prepare_openfoam_pack_tree] Skipping runtime bundle (OPENFOAM_BUNDLE_RUNTIME=${OPENFOAM_BUNDLE_RUNTIME})"
fi

printf '%s\n' "${NEW_PREFIX}" > "${NEW_PREFIX}/.pack-source-prefix"
{
  printf 'bundle=%s\n' "${OPENFOAM_BUNDLE_RUNTIME}"
  date -u +%Y-%m-%dT%H:%M:%SZ
} > "${NEW_PREFIX}/.pack-stamp"
echo "[prepare_openfoam_pack_tree] Ready at ${NEW_PREFIX} (bundle=${OPENFOAM_BUNDLE_RUNTIME})"
