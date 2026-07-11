#!/usr/bin/env bash
# Build or update the openfoam runtime image.
#
# - fresh:  FROM phynexis-build (no existing image, or FORCE=1)
# - extend: FROM existing openfoam image, rsync updated /opt/openfoam tree
#
# Usage (env vars from make):
#   DOCKER_OPENFOAM_IMAGE=openfoam:24.04-arm64 \
#   DOCKER_PLATFORM=linux/arm64 \
#   bash docker/setup_openfoam_image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

IMAGE="${DOCKER_OPENFOAM_IMAGE:?DOCKER_OPENFOAM_IMAGE required}"
PLATFORM="${DOCKER_PLATFORM:?DOCKER_PLATFORM required}"
TARGETARCH="${PLATFORM#linux/}"
DOCKERFILE="${DOCKER_DOCKERFILE:-docker/Dockerfile}"
BUILD_IMAGE_NAME="${DOCKER_BUILD_IMAGE_NAME:-phynexis-build}"
UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
NUM_JOBS="${DOCKER_JOBS:-4}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES:-0}"
FORCE="${FORCE:-0}"

verify() {
  bash "${ROOT}/docker/verify_openfoam_image.sh" "${IMAGE}"
}

run_build() {
  local target="$1"
  local -a ctx=()
  if [[ "${target}" = "extend" ]]; then
    ctx=(--build-context "extend-base=docker-image://${IMAGE}")
  fi
  DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
    "${ctx[@]}" \
    --target "${target}" \
    -f "${DOCKERFILE}" \
    --build-arg "DOCKER_BUILD_IMAGE_NAME=${BUILD_IMAGE_NAME}" \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    --build-arg "TARGETARCH=${TARGETARCH}" \
    --build-arg "NUM_JOBS=${NUM_JOBS}" \
    --build-arg "OPENFOAM_VERSION=${OPENFOAM_VERSION}" \
    --build-arg "OPENFOAM_BUILD_MODULES=${OPENFOAM_BUILD_MODULES}" \
    -t "${IMAGE}" \
    --load \
    "${ROOT}"
}

if [[ "${FORCE}" = "1" ]]; then
  printf '==> FORCE=1: creating %s from scratch (fresh)\n' "${IMAGE}"
  run_build fresh
  verify
  exit 0
fi

if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  printf '==> %s exists; updating /opt/openfoam (extend)\n' "${IMAGE}"
  run_build extend
  verify
  exit 0
fi

printf '==> Creating %s (fresh)\n' "${IMAGE}"
run_build fresh
verify
