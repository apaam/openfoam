#!/usr/bin/env bash
# Build the openfoam runtime image (fresh final stage, incremental compile via cache).
#
# Rebuilds the tagged image from phynexis-build + staged /opt/openfoam each time so
# layer size stays flat. Compile artifacts persist in the BuildKit cache mount.
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

prune_dangling() {
  local dangling=()
  mapfile -t dangling < <(docker images --filter "dangling=true" -q)
  if [[ "${#dangling[@]}" -eq 0 ]]; then
    return 0
  fi
  printf '==> Removing %s dangling image(s)\n' "${#dangling[@]}"
  docker rmi "${dangling[@]}" >/dev/null 2>&1 || true
}

run_build() {
  DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
    --target fresh \
    -f "${DOCKERFILE}" \
    --build-arg "DOCKER_BUILD_IMAGE_NAME=${BUILD_IMAGE_NAME}" \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    --build-arg "TARGETARCH=${TARGETARCH}" \
    --build-arg "NUM_JOBS=${NUM_JOBS}" \
    --build-arg "OPENFOAM_VERSION=${OPENFOAM_VERSION}" \
    --build-arg "OPENFOAM_BUILD_MODULES=${OPENFOAM_BUILD_MODULES}" \
    --build-arg "BUILD_STAMP=$(date +%s)" \
    -t "${IMAGE}" \
    --load \
    "${ROOT}"
}

if [[ "${FORCE}" = "1" ]]; then
  printf '==> FORCE=1: creating %s from scratch (fresh)\n' "${IMAGE}"
else
  printf '==> Building %s\n' "${IMAGE}"
fi

run_build
verify
prune_dangling
