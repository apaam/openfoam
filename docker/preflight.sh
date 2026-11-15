#!/usr/bin/env bash
# Ensure the build image and run scripts/ci/preflight.sh inside it.
# Host wrapper: make ci-preflight
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source "${ROOT}/docker/require_host.sh"
# shellcheck disable=SC1091
source "${ROOT}/docker/container-backend.sh"
openfoam_require_container || exit 1

PLATFORM="${DOCKER_PLATFORM:-}"
if [[ -z "${PLATFORM}" ]]; then
  case "$(uname -m)" in
  x86_64) PLATFORM=linux/amd64 ;;
  arm64 | aarch64) PLATFORM=linux/arm64 ;;
  *) PLATFORM=linux/amd64 ;;
  esac
fi
UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
BUILD_IMAGE_NAME="${DOCKER_BUILD_IMAGE_NAME:-phynexis-build}"
IMAGE="${BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${PLATFORM#linux/}"

if ! cb image inspect "${IMAGE}" >/dev/null 2>&1; then
  DOCKER_PLATFORM="${PLATFORM}" \
    DOCKER_UBUNTU_VERSION="${UBUNTU_VERSION}" \
    DOCKER_BUILD_IMAGE_NAME="${BUILD_IMAGE_NAME}" \
    FORCE=0 \
    bash "${ROOT}/docker/setup-build-image.sh"
fi

cb run --rm \
  --platform "${PLATFORM}" \
  -v "${ROOT}":"${ROOT}" \
  -w "${ROOT}" \
  "${IMAGE}" \
  bash scripts/ci/preflight.sh
