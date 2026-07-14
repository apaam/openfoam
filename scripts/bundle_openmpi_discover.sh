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

# Walk ancestors looking for share/openmpi (prefix, multiarch, Cellar layouts).
_openmpi_share_from_anchor() {
  local walk="$1"
  local i
  [[ -n "${walk}" ]] || return 1
  for i in 1 2 3 4 5 6; do
    [[ -n "${walk}" && "${walk}" != / ]] || break
    if [[ -d "${walk}/share/openmpi" ]]; then
      printf '%s/share/openmpi' "${walk}"
      return 0
    fi
    # Debian multiarch: /usr/lib/x86_64-linux-gnu -> /usr/share/openmpi
    if [[ -d "${walk}/../share/openmpi" ]]; then
      (cd "${walk}/../share/openmpi" && pwd -P)
      return 0
    fi
    walk="$(dirname "${walk}")"
  done
  return 1
}

_openmpi_share_from_ompi_info() {
  local info="$1"
  local line val
  [[ -x "${info}" ]] || return 1
  # Prefer pkgdatadir (= …/share/openmpi); fall back to datadir/openmpi.
  while IFS= read -r line; do
    case "${line}" in
    *Pkgdatadir:*|*pkgdatadir:*)
      val="$(printf '%s' "${line}" | sed -E 's/^[^:]*:[[:space:]]*//')"
      if [[ -d "${val}" ]]; then
        printf '%s' "${val}"
        return 0
      fi
      ;;
    esac
  done < <("${info}" --path pkgdatadir 2>/dev/null || true)
  while IFS= read -r line; do
    case "${line}" in
    *Datadir:*|*datadir:*)
      val="$(printf '%s' "${line}" | sed -E 's/^[^:]*:[[:space:]]*//')"
      if [[ -d "${val}/openmpi" ]]; then
        printf '%s/openmpi' "${val}"
        return 0
      fi
      ;;
    esac
  done < <("${info}" --path datadir 2>/dev/null || true)
  return 1
}

openmpi_discover_extras_paths() {
  local stage="$1"
  local representative_bin libmpi_path mpi_libdir mca_src share_src
  local mpirun_path info_path brew_prefix cand

  OPENMPI_MCA_SRC=""
  OPENMPI_MPI_BIN_DIR=""
  OPENMPI_SHARE_SRC=""

  representative_bin="$(_openmpi_representative_bin "${stage}" || true)"
  [[ -n "${representative_bin}" && -f "${representative_bin}" ]] || {
    export OPENMPI_MCA_SRC OPENMPI_MPI_BIN_DIR OPENMPI_SHARE_SRC
    return 0
  }

  libmpi_path="$(_openmpi_libmpi_from_binary "${representative_bin}")"
  # otool may report @rpath/libmpi*.dylib; resolve via brew when needed.
  if [[ -n "${libmpi_path}" && ! -f "${libmpi_path}" ]]; then
    if [[ "${libmpi_path}" == @* ]] && command -v brew >/dev/null 2>&1; then
      brew_prefix="$(brew --prefix open-mpi 2>/dev/null || true)"
      if [[ -n "${brew_prefix}" && -d "${brew_prefix}/lib" ]]; then
        libmpi_path="$(find "${brew_prefix}/lib" -name 'libmpi*.dylib' -type f 2>/dev/null \
          | head -1 || true)"
      else
        libmpi_path=""
      fi
    else
      libmpi_path=""
    fi
  fi

  mpi_libdir=""
  if [[ -n "${libmpi_path}" && -f "${libmpi_path}" ]]; then
    mpi_libdir="$(dirname "${libmpi_path}")"
    if mca_src="$(_openmpi_mca_src_from_libdir "${mpi_libdir}")"; then
      OPENMPI_MCA_SRC="${mca_src}"
    fi
  fi

  # Prefer mpirun living next to the same prefix as libmpi / ompi_info.
  mpirun_path=""
  if [[ -n "${mpi_libdir}" ]]; then
    if share_src="$(_openmpi_share_from_anchor "${mpi_libdir}")"; then
      OPENMPI_SHARE_SRC="${share_src}"
    fi
    for cand in \
      "$(dirname "${mpi_libdir}")/bin/mpirun" \
      "${mpi_libdir}/../bin/mpirun"
    do
      if [[ -x "${cand}" ]]; then
        mpirun_path="$(cd "$(dirname "${cand}")" && pwd)/$(basename "${cand}")"
        break
      fi
    done
  fi
  if [[ -z "${mpirun_path}" ]] && command -v mpirun >/dev/null 2>&1; then
    mpirun_path="$(command -v mpirun)"
  fi
  if [[ -z "${mpirun_path}" ]] && command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix open-mpi 2>/dev/null || true)"
    if [[ -n "${brew_prefix}" && -x "${brew_prefix}/bin/mpirun" ]]; then
      mpirun_path="${brew_prefix}/bin/mpirun"
    fi
  fi
  if [[ -n "${mpirun_path}" ]]; then
    OPENMPI_MPI_BIN_DIR="$(dirname "${mpirun_path}")"
  fi

  if [[ -z "${OPENMPI_SHARE_SRC}" && -n "${OPENMPI_MPI_BIN_DIR}" ]]; then
    if share_src="$(_openmpi_share_from_anchor "${OPENMPI_MPI_BIN_DIR}")"; then
      OPENMPI_SHARE_SRC="${share_src}"
    fi
    info_path="${OPENMPI_MPI_BIN_DIR}/ompi_info"
    if [[ -z "${OPENMPI_SHARE_SRC}" ]] \
      && share_src="$(_openmpi_share_from_ompi_info "${info_path}")"; then
      OPENMPI_SHARE_SRC="${share_src}"
    fi
  fi
  if [[ -z "${OPENMPI_SHARE_SRC}" && -n "${OPENMPI_MCA_SRC}" ]]; then
    if share_src="$(_openmpi_share_from_anchor "${OPENMPI_MCA_SRC}")"; then
      OPENMPI_SHARE_SRC="${share_src}"
    fi
  fi
  if [[ -z "${OPENMPI_SHARE_SRC}" ]] && command -v ompi_info >/dev/null 2>&1; then
    if share_src="$(_openmpi_share_from_ompi_info "$(command -v ompi_info)")"; then
      OPENMPI_SHARE_SRC="${share_src}"
    fi
  fi

  export OPENMPI_MCA_SRC OPENMPI_MPI_BIN_DIR OPENMPI_SHARE_SRC
}
