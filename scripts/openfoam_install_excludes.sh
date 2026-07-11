#!/usr/bin/env bash
# Shared exclude list for OpenFOAM install tree packaging.
# build_openfoam.sh copies openfoam-source/ into build/, then Allwmake adds platforms/ and build/.
# shellcheck shell=bash

# Optional OpenFOAM components (not built by default); omit from source sync and packaging.
OPENFOAM_SOURCE_SYNC_EXCLUDES=(
  --exclude=modules/
  --exclude=plugins/
)

OPENFOAM_INSTALL_EXCLUDES=(
  --exclude=build/
  --exclude=modules/
  --exclude=plugins/
  --exclude=stage/
  --exclude=docker-dist/
  --exclude=wheel/
  --exclude=wheel-dist/
  --exclude=cpack/
  --exclude=cpack-dist/
  --exclude=share/
  --exclude=Brewfile
  --exclude=configure.sh
)

OPENFOAM_INSTALL_REQUIRED=(
  etc
  bin
  platforms
  src
  applications
  wmake
)

# GNU tar --exclude patterns (relative to install prefix root).
openfoam_pack_tar_excludes() {
  OPENFOAM_PACK_TAR_EXCLUDES=(
    ./build
    ./modules
    ./plugins
    ./stage
    ./docker-dist
    ./wheel
    ./wheel-dist
    ./cpack
    ./cpack-dist
    ./share
    ./Brewfile
    ./configure.sh
  )
}
