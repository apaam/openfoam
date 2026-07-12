#!/usr/bin/env bash
# Point runtime library search at bundled libs; drop build-machine Homebrew paths.
set -euo pipefail

STAGE="${1:?stage prefix required}"
PREFS="${STAGE}/etc/prefs.sh"
BASHRC="${STAGE}/etc/bashrc"
BUNDLED='${WM_PROJECT_DIR}/lib/bundled'
MARKER='# Bundled runtime libraries (native-dist)'

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
fi

# config.sh/setup rebuilds DYLD/LD from FOAM_LD_LIBRARY_PATH and would wipe a
# prefs-only export. Re-apply bundled path at the end of bashrc (after setup).
if ! grep -qF "${MARKER}" "${BASHRC}"; then
  cat >>"${BASHRC}" <<EOF

${MARKER}
if [ -d "${BUNDLED}" ]
then
    export OPENFOAM_BUNDLED_LIB="${BUNDLED}"
    export FOAM_LD_LIBRARY_PATH="\${OPENFOAM_BUNDLED_LIB}\${FOAM_LD_LIBRARY_PATH:+:\$FOAM_LD_LIBRARY_PATH}"
    # Drop user-site libs from portable installs.
    if [ -n "\${FOAM_USER_LIBBIN:-}" ]
    then
        FOAM_LD_LIBRARY_PATH="\$(echo "\$FOAM_LD_LIBRARY_PATH" | tr ':' '\\n' | { grep -vFx "\$FOAM_USER_LIBBIN" || true; } | paste -sd: -)"
        export FOAM_LD_LIBRARY_PATH
        unset FOAM_USER_LIBBIN
    fi
    case "\$(uname -s)" in
    Darwin)
        export DYLD_LIBRARY_PATH="\${OPENFOAM_BUNDLED_LIB}\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
        if [ -n "\${DYLD_LIBRARY_PATH:-}" ] && [ -n "\${HOME:-}" ]
        then
            DYLD_LIBRARY_PATH="\$(echo "\$DYLD_LIBRARY_PATH" | tr ':' '\\n' | { grep -v "^\$HOME/OpenFOAM/" || true; } | paste -sd: -)"
            export DYLD_LIBRARY_PATH
        fi
        export FOAM_DYLD_LIBRARY_PATH="\$DYLD_LIBRARY_PATH"
        ;;
    *)
        export LD_LIBRARY_PATH="\${OPENFOAM_BUNDLED_LIB}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        ;;
    esac
fi
EOF
fi

# Keep prefs marker for visibility (optional early hint; setup may overwrite DYLD).
if [[ -f "${PREFS}" ]] && ! grep -qF "${MARKER}" "${PREFS}"; then
  cat >>"${PREFS}" <<EOF

${MARKER}
export OPENFOAM_BUNDLED_LIB="${BUNDLED}"
EOF
fi

echo "[rewrite_openfoam_prefs] Updated ${BASHRC} (and prefs if present)"
