#!/bin/bash

NUM_JOBS=${NUM_JOBS:-2}
echo "NUM_JOBS: $NUM_JOBS"

mkdir -p v2412_build

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	rsync -ura v2412_source/* v2412_build
	cd v2412_build

	source etc/bashrc
	foamSystemCheck
	./Allwmake -j $NUM_JOBS -s -q -k
	./Allwmake -j $NUM_JOBS -s
elif [[ "$OSTYPE" == "darwin"* ]]; then
	rsync -ura v2412_source/* v2412_build
	rsync -u Brewfile_v2412 v2412_build/Brewfile
	rsync -u configure_v2412.sh v2412_build/configure.sh
	cd v2412_build

	brew bundle -f
	brew bundle check --verbose --no-upgrade
	cat Brewfile.lock.json
	bash -ex configure.sh

	source etc/bashrc
	foamSystemCheck
	./Allwmake -j $NUM_JOBS -s -q -k
	./Allwmake -j $NUM_JOBS -s
else
	echo "$OSTYPE not support"
fi
