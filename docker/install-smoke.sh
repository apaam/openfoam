#!/usr/bin/env bash
# Download a published OpenFOAM pack and run the cavity tutorial, inside the
# build image (the host may be macOS and unable to run a Linux pack).
# Host wrapper: make docker-install-smoke
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

cb run --rm \
  --platform "${PLATFORM}" \
  -v "${ROOT}:/src" \
  -w /src \
  -e "RELEASE_TAG=${RELEASE_TAG:?RELEASE_TAG required}" \
  -e "OPENFOAM_BASEURL=${OPENFOAM_BASEURL:-https://download.xiaohe.team}" \
  "${IMAGE}" \
  bash scripts/ci/install-smoke.sh
