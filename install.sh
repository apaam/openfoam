#!/bin/bash

# OpenFOAM Installation Script
# Usage: ./install.sh [version]
# Example: ./install.sh v2412

VERSION=${1:-v2412}
NUM_JOBS=${NUM_JOBS:-2}

echo "Installing OpenFOAM $VERSION with $NUM_JOBS parallel jobs"

# Create build directory
mkdir -p build

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	rsync -ura openfoam_source/* build/
	cd build

	source etc/bashrc
	foamSystemCheck
	./Allwmake -j $NUM_JOBS -s -q -k
	./Allwmake -j $NUM_JOBS -s
elif [[ "$OSTYPE" == "darwin"* ]]; then
	rsync -ura openfoam_source/* build/
	rsync -u Brewfile build/Brewfile
	rsync -u configure.sh build/configure.sh
	cd build

	brew bundle -f
	brew bundle check --verbose --no-upgrade
	cat Brewfile.lock.json
	bash -ex configure.sh

	source etc/bashrc
	foamSystemCheck
	./Allwmake -j $NUM_JOBS -s -q -k
	./Allwmake -j $NUM_JOBS -s
else
	echo "$OSTYPE not supported"
fi
