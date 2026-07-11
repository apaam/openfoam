#!/usr/bin/env bash
# Keep required-command list in sync with phynexis-v0 scripts/install_deps.sh
# required_commands().
set -euo pipefail

IMAGE="${1:-}"

if [[ -z "${IMAGE}" ]]; then
  echo "Usage: docker/verify_build_image.sh IMAGE" >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[verify_build_image] Docker image not found: ${IMAGE}" >&2
  exit 1
fi

cmd_list="cmake git rsync python3 gcc g++ gfortran mpicc mpicxx flex bison m4 patch unzip"

if ! docker run --rm "${IMAGE}" bash -c "
  missing=0
  for cmd in ${cmd_list}; do
    command -v \"\${cmd}\" >/dev/null 2>&1 \
      || { echo \"Missing: \${cmd}\" >&2; missing=1; }
  done
  if ! command -v ninja >/dev/null 2>&1 && ! command -v make >/dev/null 2>&1; then
    echo 'Missing: ninja or make' >&2
    missing=1
  fi
  exit \"\${missing}\"
"; then
  exit 1
fi

echo "[verify_build_image] OK: ${IMAGE}"
