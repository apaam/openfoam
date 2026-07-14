#!/usr/bin/env bash
# Build the phynexis-build image (Ubuntu + OpenFOAM build deps).
#
# Usage:
#   bash docker/setup_build_image.sh
#   FORCE=1 bash docker/setup_build_image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source "${ROOT}/docker/require_host.sh"
openfoam_require_docker || exit 1

UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
BUILD_IMAGE_NAME="${DOCKER_BUILD_IMAGE_NAME:-phynexis-build}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"

PLATFORM="${DOCKER_PLATFORM:-}"
if [[ -z "${PLATFORM}" ]]; then
  case "$(uname -m)" in
  x86_64) PLATFORM=linux/amd64 ;;
  arm64|aarch64) PLATFORM=linux/arm64 ;;
  *) PLATFORM=linux/amd64 ;;
  esac
fi
case "${PLATFORM}" in
linux/*) ;;
*)
  echo "[setup_build_image] DOCKER_PLATFORM must be linux/* (got ${PLATFORM})" >&2
  exit 1
  ;;
esac
TARGETARCH="${PLATFORM#linux/}"
IMAGE="${BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}"

if ! docker buildx version >/dev/null 2>&1; then
  echo "[setup_build_image] docker buildx is required" >&2
  exit 1
fi

if [[ "${FORCE:-}" != "1" ]] && docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "==> ${IMAGE} already exists, skipping (FORCE=1 to rebuild)"
  exit 0
fi

printf '==> Building %s (%s)\n' "${IMAGE}" "${PLATFORM}"
DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
  -f docker/Dockerfile.build \
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
  --build-arg "APT_MIRROR=${APT_MIRROR}" \
  --build-arg "TARGETARCH=${TARGETARCH}" \
  -t "${IMAGE}" \
  --load \
  "${ROOT}"

printf '==> Ready: %s\n' "${IMAGE}"
