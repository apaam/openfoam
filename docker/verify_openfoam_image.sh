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

if ! docker run --rm "${IMAGE}" bash -lc '
  source /opt/openfoam/etc/bashrc
  missing=0
  for cmd in blockMesh; do
    bin="$(command -v "${cmd}" 2>/dev/null || true)"
    [[ -n "${bin}" ]] || continue
    while read -r line; do
      echo "Missing lib for ${cmd}: ${line}" >&2
      missing=1
    done < <(ldd "${bin}" 2>/dev/null | grep "not found" || true)
  done
  exit "${missing}"
'; then
  exit 1
fi

echo "[verify_openfoam_image] OK: ${IMAGE}"
