#!/usr/bin/env bash
# Verify a dist-native pack inside the build image (glibc floor, ldd, bashrc).
# Host wrapper: make docker-verify-pack
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
  -e "GLIBC_FLOOR=${GLIBC_FLOOR:-2.35}" \
  -e "BUILD_ROOT=${BUILD_ROOT:-docker-build}" \
  "${IMAGE}" \
  bash scripts/ci/verify-pack.sh
