#!/usr/bin/env bash
# Bundle OpenMPI MCA plugins (dlopen) and launcher binaries for parallel runs.
set -euo pipefail

STAGE="${1:?stage prefix required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="${STAGE}/lib/bundled"
MCA_SRC="${OPENMPI_MCA_SRC:-}"
MPI_BIN_DIR="${OPENMPI_MPI_BIN_DIR:-}"
FIX_RPATH="${ROOT}/scripts/bundle_fix_rpath.sh"
platform="$(uname -s)"

if [[ ! -d "${RUNTIME_DIR}" ]]; then
  echo "[bundle_openmpi_extras] Missing ${RUNTIME_DIR}; skip" >&2
  exit 0
fi

has_bundled_mpi=false
shopt -s nullglob
for _lib in "${RUNTIME_DIR}"/libmpi.so* "${RUNTIME_DIR}"/libmpi*.dylib; do
  has_bundled_mpi=true
  break
done
shopt -u nullglob

if [[ "${has_bundled_mpi}" != true ]]; then
  echo "[bundle_openmpi_extras] No bundled libmpi; skip"
  exit 0
fi

if [[ -z "${MCA_SRC}" && -z "${MPI_BIN_DIR}" ]]; then
  echo "[bundle_openmpi_extras] No system OpenMPI layout found; skip"
  exit 0
fi

mca_has_plugins() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 1
  find "${dir}" \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) -print -quit 2>/dev/null | grep -q .
}

if [[ -n "${MCA_SRC}" ]] && mca_has_plugins "${MCA_SRC}"; then
  dest="${RUNTIME_DIR}/openmpi"
  echo "[bundle_openmpi_extras] MCA ${MCA_SRC} -> ${dest}"
  rm -rf "${dest}"
  cp -a "${MCA_SRC}" "${dest}"
fi

if [[ -n "${MPI_BIN_DIR}" && -d "${MPI_BIN_DIR}" ]]; then
  mpi_bin_dest="${RUNTIME_DIR}/mpi-bin"
  mkdir -p "${mpi_bin_dest}"
  case "${platform}" in
  Darwin) marker='@executable_path/..' ;;
  *) marker='$ORIGIN/..' ;;
  esac
  search_paths="${RUNTIME_DIR}:${mpi_bin_dest}"
  bundled=0
  for cmd in mpirun mpiexec orterun orted; do
    src="${MPI_BIN_DIR}/${cmd}"
    [[ -x "${src}" ]] || continue
    dest="${mpi_bin_dest}/${cmd}"
    cp -f "${src}" "${dest}"
    chmod u+w "${dest}" 2>/dev/null || true
    FIX_RPATH_SEARCH_PATHS="${search_paths}" \
      "${FIX_RPATH}" "${dest}" "${RUNTIME_DIR}" "${marker}" "${search_paths}"
    bundled=$((bundled + 1))
  done
  if ((bundled > 0)); then
    echo "[bundle_openmpi_extras] Bundled ${bundled} MPI launcher(s) -> ${mpi_bin_dest}/"
  fi
fi

echo "[bundle_openmpi_extras] Done"
