#!/usr/bin/env bash
# Compile OpenFOAM in phynexis-build with the repo bind-mounted (same flow as local make).
#
# Paths come from docs/make-config-default.mk (OPENFOAM_BUILD / DOCKER_OPENFOAM_*).
#
# Usage (env vars from make / setup_openfoam_image.sh):
#   DOCKER_BUILD_IMAGE=phynexis-build:24.04-arm64 \
#   DOCKER_PLATFORM=linux/arm64 \
#   bash docker/compile_openfoam.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"

BUILD_IMAGE="${DOCKER_BUILD_IMAGE:?DOCKER_BUILD_IMAGE required}"
PLATFORM="${DOCKER_PLATFORM:?DOCKER_PLATFORM required}"
OPENFOAM_BUILD="${DOCKER_OPENFOAM_BUILD:?DOCKER_OPENFOAM_BUILD required}"
OPENFOAM_STAGE="${DOCKER_OPENFOAM_STAGE:?DOCKER_OPENFOAM_STAGE required}"
openfoam_load_build_paths "${ROOT}"
NUM_JOBS="${DOCKER_JOBS:-4}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES:-0}"
FORCE="${FORCE:-0}"

mkdir -p "${ROOT}/${OPENFOAM_BUILD}" "${ROOT}/${OPENFOAM_STAGE}"

printf '==> Compiling in %s (platform=%s, jobs=%s)\n' \
  "${OPENFOAM_BUILD}" "${PLATFORM}" "${NUM_JOBS}"

docker run --rm \
  --platform "${PLATFORM}" \
  -v "${ROOT}:/build/openfoam:rw" \
  -w /build/openfoam \
  -e OPENFOAM_VERSION="${OPENFOAM_VERSION}" \
  -e NUM_JOBS="${NUM_JOBS}" \
  -e OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES}" \
  -e OPENFOAM_BUILD="${OPENFOAM_BUILD}" \
  -e OPENFOAM_STAGE="${OPENFOAM_STAGE}" \
  -e FORCE="${FORCE}" \
  "${BUILD_IMAGE}" \
  bash docker/bake_openfoam.sh
