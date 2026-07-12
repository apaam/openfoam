#!/usr/bin/env bash
# Build the openfoam runtime image:
#   1. docker run + bind mount -> DOCKER_OPENFOAM_BUILD (same scripts as local make)
#   2. docker build fresh stage from DOCKER_OPENFOAM_STAGE via --build-context
#
# Usage (env vars from make):
#   DOCKER_OPENFOAM_IMAGE=openfoam:24.04-arm64 \
#   DOCKER_PLATFORM=linux/arm64 \
#   bash docker/setup_openfoam_image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
openfoam_load_build_paths "${ROOT}"

IMAGE="${DOCKER_OPENFOAM_IMAGE:?DOCKER_OPENFOAM_IMAGE required}"
PLATFORM="${DOCKER_PLATFORM:?DOCKER_PLATFORM required}"
TARGETARCH="${PLATFORM#linux/}"
DOCKERFILE="${DOCKER_DOCKERFILE:-docker/Dockerfile}"
BUILD_IMAGE="${DOCKER_BUILD_IMAGE:?DOCKER_BUILD_IMAGE required}"
UBUNTU_IMAGE_NAME="${DOCKER_UBUNTU_IMAGE_NAME:-phynexis-ubuntu}"
UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"
RUNTIME_DEPS_REV="${OPENFOAM_RUNTIME_DEPS_REV:-1}"
NUM_JOBS="${DOCKER_JOBS:-4}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES:-0}"
FORCE="${FORCE:-0}"

STAGE_DIR="$(openfoam_abs_under_root "${ROOT}" "${DOCKER_OPENFOAM_STAGE}")"

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

require_stage() {
  if [[ ! -f "${STAGE_DIR}/etc/bashrc" ]]; then
    printf 'Missing %s/etc/bashrc after compile\n' "${DOCKER_OPENFOAM_STAGE}" >&2
    exit 1
  fi
  if [[ ! -f "${STAGE_DIR}/runtime-apt.txt" ]]; then
    printf 'Missing %s/runtime-apt.txt after compile\n' "${DOCKER_OPENFOAM_STAGE}" >&2
    exit 1
  fi
}

run_image_build() {
  DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
    --build-context "of-stage=${STAGE_DIR}" \
    --target fresh \
    -f "${DOCKERFILE}" \
    --build-arg "DOCKER_UBUNTU_IMAGE_NAME=${UBUNTU_IMAGE_NAME}" \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    --build-arg "APT_MIRROR=${APT_MIRROR}" \
    --build-arg "OPENFOAM_RUNTIME_DEPS_REV=${RUNTIME_DEPS_REV}" \
    --build-arg "TARGETARCH=${TARGETARCH}" \
    --build-arg "DOCKER_OPENFOAM_BUILD=${DOCKER_OPENFOAM_BUILD}" \
    -t "${IMAGE}" \
    --load \
    "${ROOT}"
}

if [[ "${FORCE}" = "1" ]]; then
  printf '==> FORCE=1: compile + image %s\n' "${IMAGE}"
else
  printf '==> Building %s\n' "${IMAGE}"
fi

DOCKER_BUILD_IMAGE="${BUILD_IMAGE}" \
  DOCKER_PLATFORM="${PLATFORM}" \
  DOCKER_JOBS="${NUM_JOBS}" \
  OPENFOAM_VERSION="${OPENFOAM_VERSION}" \
  OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES}" \
  FORCE="${FORCE}" \
  bash "${ROOT}/docker/compile_openfoam.sh"

require_stage
run_image_build
verify
prune_dangling
