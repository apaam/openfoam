#!/usr/bin/env bash
# Discover system OpenMPI MCA + launcher paths before rpath rewriting (pack time).
set -euo pipefail

_openmpi_mca_src_from_libdir() {
  local libdir="$1"
  if [[ -d "${libdir}/openmpi/lib/openmpi3" ]]; then
    printf '%s/openmpi' "${libdir}"
    return 0
  fi
  if [[ -d "${libdir}/openmpi" ]] \
    && find "${libdir}/openmpi" \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) \
      -print -quit 2>/dev/null | grep -q .; then
    printf '%s/openmpi' "${libdir}"
    return 0
  fi
  return 1
}

openmpi_discover_extras_paths() {
  local stage="$1"
  local platform representative_bin libmpi_path mpi_libdir mca_src

  OPENMPI_MCA_SRC=""
  OPENMPI_MPI_BIN_DIR=""

  representative_bin="$(find "${stage}/platforms" -name blockMesh -type f 2>/dev/null | head -1)"
  [[ -n "${representative_bin}" && -f "${representative_bin}" ]] || return 0

  case "${platform:-$(uname -s)}" in
  Linux)
    libmpi_path="$(ldd "${representative_bin}" 2>/dev/null \
      | grep 'libmpi\.so' | head -1 | awk '/=>/ {print $3}')"
    ;;
  Darwin)
    libmpi_path="$(otool -L "${representative_bin}" 2>/dev/null \
      | grep -E 'libmpi.*\.dylib' | head -1 | awk '{print $1}')"
    ;;
  *)
    return 0
    ;;
  esac

  if [[ -n "${libmpi_path}" && -f "${libmpi_path}" ]]; then
    mpi_libdir="$(dirname "${libmpi_path}")"
    if mca_src="$(_openmpi_mca_src_from_libdir "${mpi_libdir}")"; then
      OPENMPI_MCA_SRC="${mca_src}"
    fi
  fi

  if command -v mpirun >/dev/null 2>&1; then
    OPENMPI_MPI_BIN_DIR="$(dirname "$(command -v mpirun)")"
  elif command -v brew >/dev/null 2>&1; then
    local brew_prefix
    brew_prefix="$(brew --prefix open-mpi 2>/dev/null || true)"
    if [[ -n "${brew_prefix}" && -d "${brew_prefix}/bin" ]]; then
      OPENMPI_MPI_BIN_DIR="${brew_prefix}/bin"
    fi
  fi

  export OPENMPI_MCA_SRC OPENMPI_MPI_BIN_DIR
}
