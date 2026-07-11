#!/usr/bin/env bash
# Point runtime library search at bundled libs; drop build-machine Homebrew paths.
set -euo pipefail

STAGE="${1:?stage prefix required}"
PREFS="${STAGE}/etc/prefs.sh"
BUNDLED='${WM_PROJECT_DIR}/lib/bundled'

if [[ ! -f "${PREFS}" ]]; then
  exit 0
fi

sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

case "$(uname -s)" in
Darwin)
  sed_inplace \
    -e '/\/opt\/homebrew\//d' \
    -e '/\/usr\/local\/opt\//d' \
    -e '/\/usr\/local\/Cellar\//d' \
    "${PREFS}"
  if ! grep -q 'OPENFOAM_BUNDLED_LIB' "${PREFS}"; then
    cat >>"${PREFS}" <<EOF

# Bundled runtime libraries (wheel/cpack dist)
export OPENFOAM_BUNDLED_LIB="${BUNDLED}"
export DYLD_LIBRARY_PATH="\${OPENFOAM_BUNDLED_LIB}\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
EOF
  fi
  ;;
Linux)
  sed_inplace \
    -e '/\/usr\/local\//d' \
    "${PREFS}"
  if ! grep -q 'OPENFOAM_BUNDLED_LIB' "${PREFS}"; then
    cat >>"${PREFS}" <<EOF

# Bundled runtime libraries (wheel/cpack dist)
export OPENFOAM_BUNDLED_LIB="${BUNDLED}"
export LD_LIBRARY_PATH="\${OPENFOAM_BUNDLED_LIB}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
  fi
  ;;
esac

echo "[rewrite_openfoam_prefs] Updated ${PREFS}"
