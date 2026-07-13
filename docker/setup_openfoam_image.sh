#!/usr/bin/env bash
# Build the openfoam runtime image from a linux dist-native archive.
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
case "${PLATFORM}" in
linux/*) ;;
*)
  echo "[setup_openfoam_image] DOCKER_PLATFORM must be linux/* (got ${PLATFORM})" >&2
  exit 1
  ;;
esac
TARGETARCH="${PLATFORM#linux/}"
DOCKERFILE="docker/Dockerfile"
UBUNTU_IMAGE_NAME="${DOCKER_UBUNTU_IMAGE_NAME:-phynexis-ubuntu}"
UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
DIST_VERSION="${OPENFOAM_VERSION#v}"
DIST_DIR="$(openfoam_abs_under_root "${ROOT}" "${DIST_NATIVE_DIR:-${BUILD_ROOT:-build}/dist-native}")"
BUILD_DOCKER_DIR="$(openfoam_abs_under_root "${ROOT}" "${BUILD_DOCKER_DIR:-${BUILD_ROOT:-build}/docker}")"
IMAGE_TAR="${DOCKER_IMAGE_TAR:-${BUILD_DOCKER_DIR}/openfoam-docker-${DIST_VERSION}-linux-${TARGETARCH}.tar.gz}"
CONTEXT_DIR="${BUILD_DOCKER_DIR}/of-dist-context"

arch_globs() {
  case "${TARGETARCH}" in
  amd64) printf '%s\n' 'x86_64' 'amd64' ;;
  arm64) printf '%s\n' 'arm64' 'aarch64' ;;
  *) printf '%s\n' "${TARGETARCH}" ;;
  esac
}

find_linux_native_archive() {
  local arch name candidate base
  if [[ -n "${OPENFOAM_NATIVE_DIST:-}" ]]; then
    candidate="${OPENFOAM_NATIVE_DIST}"
    case "${candidate}" in
    /*) ;;
    *) candidate="${ROOT}/${candidate}" ;;
    esac
    if [[ ! -f "${candidate}" ]]; then
      echo "[setup_openfoam_image] OPENFOAM_NATIVE_DIST not found: ${candidate}" >&2
      return 1
    fi
    base="$(basename "${candidate}")"
    case "${base}" in
    *darwin*)
      echo "[setup_openfoam_image] Docker images are Linux-only; refusing darwin archive:" >&2
      echo "  ${base}" >&2
      echo "[setup_openfoam_image] On macOS install with: make dist-native" >&2
      return 1
      ;;
    *linux*) ;;
    *)
      echo "[setup_openfoam_image] Expected a linux native archive name (*-linux-*), got: ${base}" >&2
      return 1
      ;;
    esac
    printf '%s' "${candidate}"
    return 0
  fi

  while IFS= read -r arch; do
    name="openfoam-native-${DIST_VERSION}-linux-${arch}.tar.gz"
    candidate="${DIST_DIR}/${name}"
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done < <(arch_globs)

  echo "[setup_openfoam_image] Missing linux native dist for ${PLATFORM}" >&2
  echo "[setup_openfoam_image] Docker images are always Linux (no macOS Docker image)." >&2
  echo "[setup_openfoam_image] Expected under ${DIST_DIR}/:" >&2
  while IFS= read -r arch; do
    echo "  openfoam-native-${DIST_VERSION}-linux-${arch}.tar.gz" >&2
  done < <(arch_globs)
  shopt -s nullglob
  local darwin_archives=("${DIST_DIR}"/openfoam-native-"${DIST_VERSION}"-darwin-*.tar.gz)
  shopt -u nullglob
  if [[ ${#darwin_archives[@]} -gt 0 ]]; then
    echo "[setup_openfoam_image] Found darwin archive(s) for native install only:" >&2
    for a in "${darwin_archives[@]}"; do
      echo "  $(basename "${a}")" >&2
    done
  fi
  return 1
}

verify() {
  bash "${ROOT}/docker/verify_openfoam_image.sh" "${IMAGE}"
}

prune_dangling() {
  local ids
  ids="$(docker images --filter "dangling=true" -q || true)"
  if [[ -z "${ids}" ]]; then
    return 0
  fi
  printf '==> Removing dangling image(s)\n'
  # shellcheck disable=SC2086
  docker rmi ${ids} >/dev/null 2>&1 || true
}

ARCHIVE=""
if ! ARCHIVE="$(find_linux_native_archive)"; then
  echo "[setup_openfoam_image] Build one with: make dist-native (Linux) or make docker-dist-native" >&2
  echo "[setup_openfoam_image] Or set OPENFOAM_NATIVE_DIST to a *-linux-*.tar.gz" >&2
  exit 1
fi
printf '==> Packaging %s -> image %s\n' "${ARCHIVE}" "${IMAGE}"

UBUNTU_VERSION="${UBUNTU_VERSION}" \
  DOCKER_UBUNTU_IMAGE_NAME="${UBUNTU_IMAGE_NAME}" \
  PLATFORM="${PLATFORM}" \
  bash "${ROOT}/docker/setup_base_image.sh"

mkdir -p "${CONTEXT_DIR}"
cp "${ARCHIVE}" "${CONTEXT_DIR}/openfoam-native.tar.gz"

DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
  --build-context "of-dist=${CONTEXT_DIR}" \
  -f "${DOCKERFILE}" \
  --build-arg "DOCKER_UBUNTU_IMAGE_NAME=${UBUNTU_IMAGE_NAME}" \
  --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
  --build-arg "APT_MIRROR=${APT_MIRROR}" \
  --build-arg "TARGETARCH=${TARGETARCH}" \
  -t "${IMAGE}" \
  --load \
  "${ROOT}"

verify
prune_dangling

mkdir -p "$(dirname "${IMAGE_TAR}")"
printf '==> Saving %s -> %s\n' "${IMAGE}" "${IMAGE_TAR}"
docker save "${IMAGE}" | gzip > "${IMAGE_TAR}"
ls -la "${IMAGE_TAR}"
