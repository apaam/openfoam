#!/usr/bin/env bash
# Build or extend the shared phynexis-build toolchain image.
#
# - fresh:  FROM phynexis-ubuntu (no existing image, or FORCE=1)
# - extend: FROM existing phynexis-build, apt install missing packages only
#
# Usage (env vars from make):
#   DOCKER_BUILD_IMAGE=phynexis-build:24.04-arm64 \
#   DOCKER_PLATFORM=linux/arm64 \
#   bash docker/setup_build_image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

IMAGE="${DOCKER_BUILD_IMAGE:?DOCKER_BUILD_IMAGE required}"
PLATFORM="${DOCKER_PLATFORM:?DOCKER_PLATFORM required}"
DOCKERFILE="${DOCKER_DOCKERFILE_BUILD:-docker/Dockerfile.build}"
UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
UBUNTU_IMAGE_NAME="${DOCKER_UBUNTU_IMAGE_NAME:-phynexis-ubuntu}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"
DEPS_REV="${PHYNEXIS_BUILD_DEPS_REV:-1}"
FORCE="${FORCE:-0}"

verify() {
  bash "${ROOT}/docker/verify_build_image.sh" "${IMAGE}"
}

image_rev() {
  docker image inspect "${IMAGE}" \
    --format '{{index .Config.Labels "org.phynexis.build-deps-rev"}}' 2>/dev/null \
    || true
}

run_build() {
  local target="$1"
  shift
  local -a ctx=()
  if [[ "${target}" = "extend" ]]; then
    ctx=(--build-context "extend-base=docker-image://${IMAGE}")
  fi
  DOCKER_BUILDKIT=1 docker buildx build --platform "${PLATFORM}" \
    "${ctx[@]}" \
    --target "${target}" \
    -f "${DOCKERFILE}" \
    --build-arg "DOCKER_UBUNTU_IMAGE_NAME=${UBUNTU_IMAGE_NAME}" \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    --build-arg "APT_MIRROR=${APT_MIRROR}" \
    --build-arg "PHYNEXIS_BUILD_DEPS_REV=${DEPS_REV}" \
    -t "${IMAGE}" \
    --load \
    "${ROOT}"
}

if [[ "${FORCE}" = "1" ]]; then
  printf '==> FORCE=1: rebuilding %s from %s (fresh)\n' \
    "${IMAGE}" "${UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}"
  run_build fresh
  verify
  exit 0
fi

if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  current_rev="$(image_rev)"
  if [[ -n "${current_rev}" && "${current_rev}" != "${DEPS_REV}" ]]; then
    printf '==> %s deps rev %s -> %s; extending (incremental)\n' \
      "${IMAGE}" "${current_rev}" "${DEPS_REV}"
    run_build extend
    verify
    exit 0
  fi
  if verify; then
    printf '==> %s OK, skipping docker-setup-build\n' "${IMAGE}"
    exit 0
  fi
  printf '==> %s missing toolchain deps; extending (incremental)\n' "${IMAGE}"
  run_build extend
  verify
  exit 0
fi

printf '==> Creating %s from %s (fresh)\n' \
  "${IMAGE}" "${UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}"
run_build fresh
verify
