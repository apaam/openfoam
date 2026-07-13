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

# Entrypoint loads /root/.bashrc (OF + bundled mpi-bin PATH).
# Bypass entrypoint for the existence check so a sourcing failure is not
# misreported as a missing file.
if ! docker run --rm --entrypoint test "${IMAGE}" -f /root/.bashrc; then
  echo "Missing /root/.bashrc" >&2
  exit 1
fi

if ! docker run --rm "${IMAGE}" bash -c 'command -v blockMesh >/dev/null'; then
  echo "blockMesh not on PATH after entrypoint / root.bashrc" >&2
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
      find /opt/openfoam/lib/bundled/openmpi \
        \( -name "mca_*.so" -o -name "mca_*.dylib" \) -type f 2>/dev/null \
        | head -1 || true
    )"
    if [[ -z "${mca_file}" ]]; then
      echo "Missing OpenMPI MCA plugins under /opt/openfoam/lib/bundled/openmpi" >&2
      missing=1
    fi
    if find /opt/openfoam/lib/bundled/openmpi -name "mca_pmix*" -type f 2>/dev/null \
      | grep -q .; then
      if ! ls /opt/openfoam/lib/bundled/libpmix.so* >/dev/null 2>&1; then
        echo "Missing bundled libpmix (required by OpenMPI MCA pmix)" >&2
        missing=1
      fi
    fi
  elif [[ -d /opt/openfoam/lib/bundled ]]; then
    echo "mpirun not on PATH (root.bashrc should prepend lib/bundled/mpi-bin)" >&2
    missing=1
  fi
  if grep -qF "Bundled runtime libraries (dist-native)" /opt/openfoam/etc/bashrc \
    || grep -qF "Bundled OpenMPI relocation (dist-native)" /opt/openfoam/etc/bashrc; then
    echo "etc/bashrc still contains dist-native bundled patches" >&2
    missing=1
  fi
  if ! grep -qF "/opt/openfoam/etc/bashrc" /root/.bashrc; then
    echo "/root/.bashrc does not source OpenFOAM etc/bashrc" >&2
    missing=1
  fi
  exit "${missing}"
'; then
  exit 1
fi

echo "[verify_openfoam_image] OK: ${IMAGE}"
