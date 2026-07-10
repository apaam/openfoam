#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_ROOT="/build/openfoam"
OPENFOAM_BUILD="${OPENFOAM_ROOT}/build"
CACHE_BUILD="/cache/openfoam/build"
NUM_JOBS="${NUM_JOBS:-$(nproc)}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"

cd "${OPENFOAM_ROOT}"

if [[ ! -d "${OPENFOAM_BUILD}/etc" && -d "${CACHE_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Seeding build/ from cache -> ${OPENFOAM_BUILD}"
  mkdir -p "${OPENFOAM_BUILD}"
  rsync -a "${CACHE_BUILD}/" "${OPENFOAM_BUILD}/"
fi

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Building OpenFOAM ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
  NUM_JOBS="${NUM_JOBS}" bash install.sh "${OPENFOAM_VERSION}"
fi

if [[ -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Refreshing cache (${CACHE_BUILD}/)"
  mkdir -p "${CACHE_BUILD}"
  rsync -a "${OPENFOAM_BUILD}/" "${CACHE_BUILD}/"
fi

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

echo "[bake_openfoam] OpenFOAM install ready at ${OPENFOAM_BUILD}"
