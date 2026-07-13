#!/usr/bin/env bash
# Clean build-machine prefs for portable packs. Does not patch etc/bashrc.
#
# Bundled third-party libs live under lib/bundled and are found via rpath.
# OpenMPI OPAL/MCA env is set by lib/bundled/mpi-bin wrappers (openfoam_mpi_env.sh).
# Optional PATH to mpi-bin belongs in CLI / outer product bashrc, not OpenFOAM bashrc.
set -euo pipefail

STAGE="${1:?stage prefix required}"
PREFS="${STAGE}/etc/prefs.sh"
BASHRC="${STAGE}/etc/bashrc"
PREFS_SYS_OPENMPI="${STAGE}/etc/config.sh/prefs.sys-openmpi"
MARKER='# Bundled runtime libraries (dist-native)'
MPI_MARKER='# Bundled OpenMPI relocation (dist-native)'

if [[ ! -f "${BASHRC}" ]]; then
  echo "[rewrite_openfoam_prefs] Missing ${BASHRC}" >&2
  exit 1
fi

sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Drop build-machine third-party paths from prefs (Homebrew / local prefixes).
if [[ -f "${PREFS}" ]]; then
  case "$(uname -s)" in
  Darwin)
    sed_inplace \
      -e '/\/opt\/homebrew\//d' \
      -e '/\/usr\/local\/opt\//d' \
      -e '/\/usr\/local\/Cellar\//d' \
      "${PREFS}"
    ;;
  Linux)
    sed_inplace \
      -e '/\/usr\/local\//d' \
      "${PREFS}"
    ;;
  esac
  # Remove legacy bundled hint if present.
  if grep -qF "${MARKER}" "${PREFS}"; then
    awk -v marker="${MARKER}" '
      $0 == marker { skip=1; next }
      skip && /^export OPENFOAM_BUNDLED_LIB=/ { skip=0; next }
      skip { next }
      { print }
    ' "${PREFS}" >"${PREFS}.tmp"
    mv "${PREFS}.tmp" "${PREFS}"
  fi
fi

# Strip legacy dist-native patches previously appended to bashrc.
strip_bashrc_marker_block() {
  local marker="$1"
  if ! grep -qF "${marker}" "${BASHRC}"; then
    return 0
  fi
  # Delete from marker through the closing "fi" of that block (blank line before next section ok).
  awk -v marker="${marker}" '
    $0 == marker { skip=1; next }
    skip && /^fi$/ { skip=0; next }
    skip { next }
    { print }
  ' "${BASHRC}" >"${BASHRC}.tmp"
  mv "${BASHRC}.tmp" "${BASHRC}"
  echo "[rewrite_openfoam_prefs] Removed legacy bashrc block: ${marker}"
}

strip_bashrc_marker_block "${MARKER}"
strip_bashrc_marker_block "${MPI_MARKER}"

# Remove generated prefs that hard-wired bundled OpenMPI into SYSTEMOPENMPI discovery.
if [[ -f "${PREFS_SYS_OPENMPI}" ]] && grep -qF 'rewrite_openfoam_prefs.sh' "${PREFS_SYS_OPENMPI}"; then
  rm -f "${PREFS_SYS_OPENMPI}"
  echo "[rewrite_openfoam_prefs] Removed ${PREFS_SYS_OPENMPI}"
fi

echo "[rewrite_openfoam_prefs] Cleaned prefs; etc/bashrc left without dist-native patches"
