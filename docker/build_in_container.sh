#!/usr/bin/env bash
# Interactive shell in phynexis-build. Repo is bind-mounted; make uses
# CONTAINER_BUILD=1 so outputs go under build/docker/ (isolated from host build/).
#
#   make docker-shell
#   # inside: make dist-native && make dist-docker
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

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

if ! command -v docker >/dev/null 2>&1; then
  echo "[build_in_container] docker not found" >&2
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
  bash "${ROOT}/docker/setup_build_image.sh"

mkdir -p "${ROOT}/build/docker"

docker_sock_args=()
if [[ -S /var/run/docker.sock ]]; then
  docker_sock_args=(-v /var/run/docker.sock:/var/run/docker.sock)
else
  echo "[build_in_container] WARNING: /var/run/docker.sock missing;" >&2
  echo "[build_in_container]          make dist-docker inside this shell will fail." >&2
fi

printf '==> Shell in %s (%s); tree=build/docker/ (CONTAINER_BUILD=1)\n' \
  "${IMAGE}" "${PLATFORM}"
printf '    Example: make dist-native && make dist-docker\n'

docker run --rm -it \
  --platform "${PLATFORM}" \
  -v "${ROOT}:/src" \
  -w /src \
  "${docker_sock_args[@]}" \
  -e "DEBIAN_FRONTEND=noninteractive" \
  -e "BUILD_JOBS=${BUILD_JOBS}" \
  -e "NUM_JOBS=${BUILD_JOBS}" \
  -e "OPENFOAM_VERSION=${OPENFOAM_VERSION}" \
  -e "CONTAINER_BUILD=1" \
  "${IMAGE}" \
  bash -l
