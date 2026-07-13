#!/usr/bin/env bash
# Non-interactive: compile + dist-native into docker-build/ (CONTAINER_BUILD=1).
# Used by make docker-dist-native / docker-dist-docker.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck disable=SC1091
source "${ROOT}/docker/require_host.sh"
openfoam_require_docker_host "docker-dist" || exit 1

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
CONTAINER_BUILD=1 openfoam_load_build_paths "${ROOT}"

PLATFORM="${DOCKER_PLATFORM:-}"
if [[ -z "${PLATFORM}" ]]; then
  case "$(uname -m)" in
  x86_64) PLATFORM=linux/amd64 ;;
  arm64|aarch64) PLATFORM=linux/arm64 ;;
  *) PLATFORM=linux/amd64 ;;
  esac
fi

UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
BUILD_IMAGE_NAME="${DOCKER_BUILD_IMAGE_NAME:-phynexis-build}"
TARGETARCH="${PLATFORM#linux/}"
IMAGE="${BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"
BUILD_JOBS="${BUILD_JOBS:-${NUM_JOBS:-4}}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
FORCE="${FORCE:-0}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[compile_openfoam] docker not found" >&2
  exit 1
fi

printf '==> Ensuring openfoam-source submodule\n'
git -c submodule.recurse=false submodule sync -- openfoam-source
git -c submodule.recurse=false submodule update --init --depth 1 -- openfoam-source

printf '==> Ensuring build image %s\n' "${IMAGE}"
DOCKER_PLATFORM="${PLATFORM}" \
  DOCKER_UBUNTU_VERSION="${UBUNTU_VERSION}" \
  DOCKER_BUILD_IMAGE_NAME="${BUILD_IMAGE_NAME}" \
  DOCKER_APT_MIRROR="${APT_MIRROR}" \
  FORCE="${FORCE}" \
  bash "${ROOT}/docker/setup_build_image.sh"

mkdir -p "${ROOT}/${BUILD_ROOT}"

printf '==> Compiling dist-native in %s (%s); BUILD_ROOT=%s/\n' \
  "${IMAGE}" "${PLATFORM}" "${BUILD_ROOT}"

docker run --rm \
  --platform "${PLATFORM}" \
  -v "${ROOT}:/src" \
  -w /src \
  -e "DEBIAN_FRONTEND=noninteractive" \
  -e "BUILD_JOBS=${BUILD_JOBS}" \
  -e "NUM_JOBS=${BUILD_JOBS}" \
  -e "OPENFOAM_VERSION=${OPENFOAM_VERSION}" \
  -e "CONTAINER_BUILD=1" \
  -e "FORCE=${FORCE}" \
  "${IMAGE}" \
  make -j"${BUILD_JOBS}" dist-native
