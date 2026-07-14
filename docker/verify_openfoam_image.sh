#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/docker/require_host.sh"
openfoam_require_docker || exit 1

IMAGE="${1:-}"

if [[ -z "${IMAGE}" ]]; then
  echo "Usage: docker/verify_openfoam_image.sh IMAGE" >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[verify_openfoam_image] Docker image not found: ${IMAGE}" >&2
  exit 1
fi

# Entrypoint loads /root/.bashrc → product etc/bashrc → openfoam/etc/bashrc.
if ! docker run --rm --entrypoint test "${IMAGE}" -f /root/.bashrc; then
  echo "Missing /root/.bashrc" >&2
  exit 1
fi

if ! docker run --rm --entrypoint test "${IMAGE}" -f /opt/openfoam/openfoam/etc/bashrc; then
  echo "Missing /opt/openfoam/openfoam/etc/bashrc (upstream)" >&2
  exit 1
fi

if ! docker run --rm --entrypoint bash "${IMAGE}" -c '
  set +u
  set --
  source /opt/openfoam/etc/bashrc
  command -v blockMesh >/dev/null
'; then
  echo "blockMesh not on PATH after source /opt/openfoam/etc/bashrc" >&2
  exit 1
fi

if ! docker run --rm "${IMAGE}" blockMesh -help >/dev/null; then
  echo "blockMesh -help failed" >&2
  exit 1
fi

if ! docker run --rm "${IMAGE}" bash -c '
  missing=0
  for cmd in blockMesh; do
    bin="$(command -v "${cmd}" 2>/dev/null || true)"
    [[ -n "${bin}" ]] || continue
    while read -r line; do
      echo "Missing lib for ${cmd}: ${line}" >&2
      missing=1
    done < <(ldd "${bin}" 2>/dev/null | grep "not found" || true)
  done
  if command -v mpirun >/dev/null 2>&1; then
    if ! mpirun_out="$(mpirun --version 2>&1)"; then
      echo "Missing or broken bundled mpirun (--version)" >&2
      echo "${mpirun_out}" >&2
      missing=1
    fi
    mca_file="$(
      find /opt/openfoam/openfoam/lib/openmpi \
        \( -name "mca_*.so" -o -name "mca_*.dylib" \) -type f 2>/dev/null \
        | head -1 || true
    )"
    if [[ -z "${mca_file}" ]]; then
      echo "Missing OpenMPI MCA plugins under /opt/openfoam/openfoam/lib/openmpi" >&2
      missing=1
    fi
    if find /opt/openfoam/openfoam/lib/openmpi -name "mca_pmix*" -type f 2>/dev/null \
      | grep -q .; then
      if ! ls /opt/openfoam/openfoam/lib/libpmix.so* >/dev/null 2>&1; then
        echo "Missing bundled libpmix (required by OpenMPI MCA pmix)" >&2
        missing=1
      fi
    fi
  elif [[ -f /opt/openfoam/openfoam/lib/.bundle-stamp ]]; then
    echo "mpirun not on PATH after source etc/bashrc" >&2
    missing=1
  fi
  if ! grep -qF "openfoam/etc/bashrc" /opt/openfoam/etc/bashrc; then
    echo "etc/bashrc does not source openfoam/etc/bashrc" >&2
    missing=1
  fi
  if ! grep -qF "/opt/openfoam/etc/bashrc" /root/.bashrc; then
    echo "/root/.bashrc does not source product etc/bashrc" >&2
    missing=1
  fi
  exit "${missing}"
'; then
  exit 1
fi

echo "[verify_openfoam_image] OK: ${IMAGE}"
