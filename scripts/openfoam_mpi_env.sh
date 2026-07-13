#!/usr/bin/env bash
# Runtime env for relocated / bundled OpenMPI (Debian absolute paths break otherwise).
# Sourced by mpi-bin wrappers; BASH_SOURCE is …/lib/bundled/mpi-bin/openfoam_mpi_env.sh.
#
# Safe to source multiple times. Existing OMPI_MCA_* / OPAL_* in the environment win
# except OPAL_PREFIX/LIBDIR which always point at the bundled tree when unset-or-empty
# is not enough — we only set when unset.

_MPI_BIN="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BUNDLED="$(CDPATH= cd -- "${_MPI_BIN}/.." && pwd)"

if [[ -z "${OPAL_PREFIX:-}" ]]; then
  export OPAL_PREFIX="${_BUNDLED}"
fi
if [[ -z "${OPAL_LIBDIR:-}" ]]; then
  export OPAL_LIBDIR="${_BUNDLED}"
fi
if [[ -z "${OPAL_EXEC_PREFIX:-}" ]]; then
  export OPAL_EXEC_PREFIX="${_BUNDLED}"
fi

if [[ -d "${_BUNDLED}/share/openmpi" ]]; then
  if [[ -z "${OPAL_DATADIR:-}" ]]; then
    export OPAL_DATADIR="${_BUNDLED}/share"
  fi
  if [[ -z "${OPAL_PKGDATADIR:-}" ]]; then
    export OPAL_PKGDATADIR="${_BUNDLED}/share/openmpi"
  fi
fi

case "$(uname -s)" in
Darwin)
  case ":${DYLD_LIBRARY_PATH:-}:" in
  *":${_BUNDLED}:"*) ;;
  *) export DYLD_LIBRARY_PATH="${_BUNDLED}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}" ;;
  esac
  ;;
*)
  case ":${LD_LIBRARY_PATH:-}:" in
  *":${_BUNDLED}:"*) ;;
  *) export LD_LIBRARY_PATH="${_BUNDLED}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
  esac
  ;;
esac

if [[ -z "${OMPI_MCA_mca_base_component_path:-}" ]]; then
  _mca_file="$(
    find "${_BUNDLED}/openmpi" \
      \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) -type f 2>/dev/null \
      | head -1 || true
  )"
  if [[ -n "${_mca_file}" ]]; then
    export OMPI_MCA_mca_base_component_path="$(dirname "${_mca_file}")"
  fi
  unset _mca_file
fi

# Point PLM at the real orted (not a wrapper) when present.
if [[ -z "${OMPI_MCA_orte_launch_agent:-}" ]]; then
  if [[ -x "${_MPI_BIN}/.real/orted" ]]; then
    export OMPI_MCA_orte_launch_agent="${_MPI_BIN}/.real/orted"
  fi
fi

# Portable defaults (overridable).
if [[ -z "${OMPI_MCA_btl_base_warn_component_unused:-}" ]]; then
  export OMPI_MCA_btl_base_warn_component_unused=0
fi
# Optional netlink reachable plugin needs libnl; ignore when absent.
if [[ -z "${OMPI_MCA_reachable:-}" ]]; then
  export OMPI_MCA_reachable=^netlink
fi

unset _MPI_BIN _BUNDLED
