#!/usr/bin/env bash
# Runtime env for relocated / bundled OpenMPI (Debian absolute paths break otherwise).
# Sourced by mpi-bin wrappers; BASH_SOURCE is …/lib/mpi-bin/openfoam_mpi_env.sh.
#
# Safe to source multiple times. Existing OMPI_MCA_* / OPAL_* in the environment win
# except OPAL_PREFIX/LIBDIR which always point at the bundled tree when unset-or-empty
# is not enough — we only set when unset.
#
# Use private names so we do not unset the caller's _MPI_BIN (wrapper needs it after source).

_of_mpi_bin="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_of_bundled="$(CDPATH= cd -- "${_of_mpi_bin}/.." && pwd)"

if [[ -z "${OPAL_PREFIX:-}" ]]; then
  export OPAL_PREFIX="${_of_bundled}"
fi
if [[ -z "${OPAL_LIBDIR:-}" ]]; then
  export OPAL_LIBDIR="${_of_bundled}"
fi
if [[ -z "${OPAL_EXEC_PREFIX:-}" ]]; then
  export OPAL_EXEC_PREFIX="${_of_bundled}"
fi
# OpenMPI 5 PRTE (mpirun -> prterun) uses PRTE_PREFIX independently of OPAL_*.
if [[ -z "${PRTE_PREFIX:-}" ]]; then
  export PRTE_PREFIX="${_of_bundled}"
fi

if [[ -d "${_of_bundled}/share/openmpi" ]]; then
  if [[ -z "${OPAL_DATADIR:-}" ]]; then
    export OPAL_DATADIR="${_of_bundled}/share"
  fi
  if [[ -z "${OPAL_PKGDATADIR:-}" ]]; then
    export OPAL_PKGDATADIR="${_of_bundled}/share/openmpi"
  fi
fi

case "$(uname -s)" in
Darwin)
  case ":${DYLD_LIBRARY_PATH:-}:" in
  *":${_of_bundled}:"*) ;;
  *) export DYLD_LIBRARY_PATH="${_of_bundled}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}" ;;
  esac
  ;;
*)
  case ":${LD_LIBRARY_PATH:-}:" in
  *":${_of_bundled}:"*) ;;
  *) export LD_LIBRARY_PATH="${_of_bundled}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
  esac
  ;;
esac

if [[ -z "${OMPI_MCA_mca_base_component_path:-}" ]]; then
  _mca_file="$(
    find "${_of_bundled}/openmpi" \
      \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) -type f 2>/dev/null \
      | head -1 || true
  )"
  if [[ -n "${_mca_file}" ]]; then
    export OMPI_MCA_mca_base_component_path="$(dirname "${_mca_file}")"
  fi
  unset _mca_file
fi

# Point PLM at the real orted / prted (not a wrapper) when present.
if [[ -z "${OMPI_MCA_orte_launch_agent:-}" ]]; then
  if [[ -x "${_of_mpi_bin}/.real/orted" ]]; then
    export OMPI_MCA_orte_launch_agent="${_of_mpi_bin}/.real/orted"
  fi
fi
if [[ -z "${PRTE_MCA_prte_launch_agent:-}" ]]; then
  if [[ -x "${_of_mpi_bin}/.real/prted" ]]; then
    export PRTE_MCA_prte_launch_agent="${_of_mpi_bin}/.real/prted"
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

unset _of_mpi_bin _of_bundled
