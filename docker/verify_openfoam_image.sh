#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-}"

if [[ -z "${IMAGE}" ]]; then
  echo "Usage: docker/verify_openfoam_image.sh IMAGE" >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[verify_openfoam_image] Docker image not found: ${IMAGE}" >&2
  exit 1
fi

if ! docker run --rm "${IMAGE}" bash -lc \
  'source /opt/openfoam/etc/bashrc && command -v blockMesh >/dev/null'; then
  exit 1
fi

echo "[verify_openfoam_image] OK: ${IMAGE}"
