#!/usr/bin/env bash
set -euo pipefail

SYSTEM_COMPILER="Clang"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFS_SH="etc/prefs.sh"
PREFS_CSH="etc/prefs.csh"
for _scripts in "${ROOT}/../scripts/platform_paths.sh" "${ROOT}/scripts/platform_paths.sh"; do
  if [[ -f "${_scripts}" ]]; then
    # shellcheck source=/dev/null
    source "${_scripts}"
    break
  fi
done
unset _scripts

# Resolve brew paths first
ADIOS_PATH=$(brew --prefix adios2)
BOOST_PATH=$(brew --prefix boost)
CGAL_PATH=$(brew --prefix cgal)
CMAKE_PATH=$(brew --prefix cmake)
FFTW_PATH=$(brew --prefix fftw)
KAHIP_PATH=$(brew --prefix kahip)
METIS_PATH=$(brew --prefix metis)
SCOTCH_PATH=$(brew --prefix scotch)

LIBOMP_PATH=$(brew --prefix libomp)
GMP_PATH=$(brew --prefix gmp)
MPFR_PATH=$(brew --prefix mpfr)

# Configure OpenFOAM paths
bin/tools/foamConfigurePaths \
    -system-compiler "$SYSTEM_COMPILER" \
    -adios-path "$ADIOS_PATH"  \
    -cgal-path "$CGAL_PATH"  \
    -cmake-path "$CMAKE_PATH"  \
    -fftw-path "$FFTW_PATH"  \
    -kahip-path "$KAHIP_PATH"  \
    -metis-path "$METIS_PATH"  \
    -scotch-path "$SCOTCH_PATH"

# Manually fix boost paths (foamConfigurePaths has issues with boost)
echo "Manually configuring boost paths..."
sed -i '' "s|setenv BOOST_ARCH_PATH.*|setenv BOOST_ARCH_PATH \"$BOOST_PATH\"|" etc/config.csh/CGAL
sed -i '' "s|export BOOST_ARCH_PATH=.*|export BOOST_ARCH_PATH=\"$BOOST_PATH\"|" etc/config.sh/CGAL

# Clean up existing prefs files
rm -f "${PREFS_SH}" "${PREFS_CSH}"

# Set up include and library paths
CPATH="$BOOST_PATH/include:$CGAL_PATH/include:$LIBOMP_PATH/include:$GMP_PATH/include:$MPFR_PATH/include"
LIBRARY_PATH="$BOOST_PATH/lib:$CGAL_PATH/lib:$LIBOMP_PATH/lib:$GMP_PATH/lib:$MPFR_PATH/lib"

mkdir -p "$(dirname "${PREFS_SH}")" "$(dirname "${PREFS_CSH}")"
echo "export CPATH=\"$CPATH\"" >> "${PREFS_SH}"
echo "setenv CPATH \"$CPATH\"" >> "${PREFS_CSH}"
echo "export LIBRARY_PATH=\"$LIBRARY_PATH\"" >> "${PREFS_SH}"
echo "setenv LIBRARY_PATH \"$LIBRARY_PATH\"" >> "${PREFS_CSH}"

BREW_BIN="$(platform_paths_brew_bin || true)"
if [[ -n "${BREW_BIN}" ]]; then
  echo "export PATH=\"${BREW_BIN}:\$PATH\"" >> "${PREFS_SH}"
  echo "setenv PATH \"${BREW_BIN}:\$PATH\"" >> "${PREFS_CSH}"
fi

# Keep etc/bashrc / etc/cshrc upstream; use official prefs extension points.
if ! grep -qF 'FOAM_DYLD_LIBRARY_PATH' "${PREFS_SH}" 2>/dev/null; then
  echo 'export FOAM_DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH"' >> "${PREFS_SH}"
fi
if ! grep -qF 'FOAM_DYLD_LIBRARY_PATH' "${PREFS_CSH}" 2>/dev/null; then
  echo 'setenv FOAM_DYLD_LIBRARY_PATH "$DYLD_LIBRARY_PATH"' >> "${PREFS_CSH}"
fi

# wmake uses #!/bin/bash -> macOS /bin/bash 3.2 (no wait -n). Use env so PATH applies.
echo "Patching wmake shebangs -> /usr/bin/env bash"
grep -rl '^#!.*bash' wmake 2>/dev/null \
  | while read -r f; do
      sed -i '' '1s|^#!.*bash$|#!/usr/bin/env bash|' "$f"
    done
