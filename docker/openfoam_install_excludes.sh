# Shared rsync exclude list for OpenFOAM install tree packaging.
# build_openfoam.sh copies openfoam-source/ into build/, then Allwmake adds platforms/ and build/.
# shellcheck shell=bash

OPENFOAM_INSTALL_EXCLUDES=(
  --exclude=build/
  --exclude=modules/
  --exclude=plugins/
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
