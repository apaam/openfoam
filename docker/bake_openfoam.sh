#!/usr/bin/env bash
set -euo pipefail

# Bake OpenFOAM into the image layer at /build/openfoam-src/build.
# Optionally seed from BuildKit cache mount /cache/openfoam-src
# (id=openfoam-build-${TARGETARCH}).

OPENFOAM_ROOT="/build/openfoam-src"
OPENFOAM_BUILD="${OPENFOAM_ROOT}/build"
CACHE_SRC="${OPENFOAM_CACHE_SRC:-/cache/openfoam-src}"
NUM_JOBS="${NUM_JOBS:-$(nproc)}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"

cd "${OPENFOAM_ROOT}"

if [[ -d "${CACHE_SRC}/build/etc" && ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Seeding from BuildKit cache -> ${OPENFOAM_ROOT}"
  rsync -a "${CACHE_SRC}/" "${OPENFOAM_ROOT}/"
fi

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Building OpenFOAM ${OPENFOAM_VERSION} (jobs=${NUM_JOBS})"
  if [[ -d .git ]]; then
    git submodule sync
    git submodule update --depth 1 --init
  fi
  NUM_JOBS="${NUM_JOBS}" bash install.sh "${OPENFOAM_VERSION}"
fi

if [[ -d "${CACHE_SRC}" ]]; then
  echo "[bake_openfoam] Refreshing BuildKit cache from ${OPENFOAM_ROOT}"
  mkdir -p "${CACHE_SRC}"
  rsync -a "${OPENFOAM_ROOT}/" "${CACHE_SRC}/"
fi

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[bake_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

echo "[bake_openfoam] OpenFOAM ready at ${OPENFOAM_BUILD}"
