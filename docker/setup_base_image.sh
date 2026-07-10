#!/bin/bash
set -euo pipefail

# Prepare digest-pinned Ubuntu base (phynexis-ubuntu:* tags).
# Usage:
#   ./docker/setup_base_image.sh
#   PLATFORM=linux/amd64 ./docker/setup_base_image.sh
#   PLATFORM=all ./docker/setup_base_image.sh
#   FORCE=1 ./docker/setup_base_image.sh

UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
DOCKER_UBUNTU_IMAGE_NAME="${DOCKER_UBUNTU_IMAGE_NAME:-phynexis-ubuntu}"
SOURCE_IMAGE="ubuntu:${UBUNTU_VERSION}"

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed." >&2
    exit 1
fi
if ! docker buildx version >/dev/null 2>&1; then
    echo "ERROR: docker buildx is required but not available." >&2
    exit 1
fi

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
x86_64)  DEFAULT_PLATFORM="linux/amd64" ;;
arm64|aarch64) DEFAULT_PLATFORM="linux/arm64" ;;
*)       DEFAULT_PLATFORM="linux/amd64" ;;
esac

PLATFORM="${PLATFORM:-${DEFAULT_PLATFORM}}"

get_digest() {
    local platform="$1"
    docker buildx imagetools inspect "${SOURCE_IMAGE}" --raw 2>/dev/null \
      | jq -r --arg platform "${platform}" '
          .manifests[]
          | select(.platform.os == ($platform | split("/")[0])
               and .platform.architecture == ($platform | split("/")[1])
               and .platform.architecture != "unknown")
          | .digest'
}

pull_and_tag() {
    local platform="$1"
    local suffix="${platform#linux/}"
    local target="${DOCKER_UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}-${suffix}"

    if [[ "${FORCE:-}" != "1" ]] && docker image inspect "${target}" >/dev/null 2>&1; then
        echo "==> ${target} already exists, skipping"
        return 0
    fi

    echo "==> Resolving digest for ${SOURCE_IMAGE} platform=${platform}"
    local digest
    digest="$(get_digest "${platform}")"
    if [[ -z "${digest}" ]]; then
        echo "ERROR: could not resolve digest for ${SOURCE_IMAGE} ${platform}" >&2
        exit 1
    fi

    echo "==> Pulling ${SOURCE_IMAGE}@${digest}"
    docker pull --platform "${platform}" "${SOURCE_IMAGE}@${digest}"

    echo "==> Tagging as ${target}"
    docker tag "${SOURCE_IMAGE}@${digest}" "${target}"
}

if [[ "${PLATFORM}" == "all" ]]; then
    pull_and_tag linux/amd64
    pull_and_tag linux/arm64
else
    pull_and_tag "${PLATFORM}"
fi

echo "==> Done."
