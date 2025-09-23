#!/bin/bash

NUM_JOBS=${NUM_JOBS:-2}
echo "NUM_JOBS: $NUM_JOBS"

mkdir -p v2112_build

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	rsync -ura v2112_source/* v2112_build
	cd v2112_build

	source etc/bashrc
	foamSystemCheck
	./Allwmake -j $NUM_JOBS -s -q -k
	./Allwmake -j $NUM_JOBS -s
elif [[ "$OSTYPE" == "darwin"* ]]; then
	rsync -ura v2112_source/* v2112_build
	rsync -u Brewfile_v2112 v2112_build/Brewfile
	rsync -u configure_v2112.sh v2112_build/configure.sh
	cd v2112_build

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
