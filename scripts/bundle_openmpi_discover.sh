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

# Prefer Pstream (links libmpi); many apps like blockMesh do not.
_openmpi_representative_bin() {
  local stage="$1"
  local candidate
  candidate="$(find "${stage}/platforms" -path '*/sys-openmpi/libPstream*' \
    -type f 2>/dev/null | head -1 || true)"
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    printf '%s' "${candidate}"
    return 0
  fi
  candidate="$(find "${stage}/platforms" \
    \( -name 'libPstream.dylib' -o -name 'libPstream.so*' -o -name blockMesh \) \
    -type f 2>/dev/null | head -1 || true)"
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    printf '%s' "${candidate}"
    return 0
  fi
  return 1
}

_openmpi_libmpi_from_binary() {
  local binary="$1"
  case "$(uname -s)" in
  Linux)
    ldd "${binary}" 2>/dev/null | grep 'libmpi\.so' | head -1 \
      | awk '/=>/ {print $3}' || true
    ;;
  Darwin)
    otool -L "${binary}" 2>/dev/null | grep -E 'libmpi.*\.dylib' | head -1 \
      | awk '{print $1}' || true
    ;;
  esac
}

openmpi_discover_extras_paths() {
  local stage="$1"
  local representative_bin libmpi_path mpi_libdir mca_src

  OPENMPI_MCA_SRC=""
  OPENMPI_MPI_BIN_DIR=""

  representative_bin="$(_openmpi_representative_bin "${stage}" || true)"
  [[ -n "${representative_bin}" && -f "${representative_bin}" ]] || {
    export OPENMPI_MCA_SRC OPENMPI_MPI_BIN_DIR
    return 0
  }

  libmpi_path="$(_openmpi_libmpi_from_binary "${representative_bin}")"
  # otool may report @rpath/libmpi*.dylib; resolve via brew when needed.
  if [[ -n "${libmpi_path}" && ! -f "${libmpi_path}" ]]; then
    if [[ "${libmpi_path}" == @* ]] && command -v brew >/dev/null 2>&1; then
      local brew_lib
      brew_lib="$(brew --prefix open-mpi 2>/dev/null || true)"
      if [[ -n "${brew_lib}" && -d "${brew_lib}/lib" ]]; then
        libmpi_path="$(find "${brew_lib}/lib" -name 'libmpi*.dylib' -type f 2>/dev/null \
          | head -1 || true)"
      else
        libmpi_path=""
      fi
    else
      libmpi_path=""
    fi
  fi

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
