MAKE_PID := $(shell echo $$PPID)
JOB_FLAG := $(filter -j%, $(subst -j ,-j,$(shell ps T | grep "^\s*$(MAKE_PID).*$(MAKE)")))
JOBS     := $(subst -j,,$(JOB_FLAG))

default: get_jobs
	bash install.sh

install: get_jobs
	bash install.sh

v2112: get_jobs
	git checkout v2112
	bash install.sh v2112

v2412: get_jobs
	git checkout v2412
	bash install.sh v2412

deps:
	brew bundle -f

test: get_jobs
	bash test.sh

get_jobs:
	@if [ -n "$(JOBS)" ]; then \
		if [ "$(JOBS)" = "" ]; then \
			echo "Parallel jobs are enabled (using default jobserver mode)"; \
		else \
			echo "Parallel jobs: $(JOBS)"; \
		fi; \
	else \
		echo "No parallel jobs specified (using default jobserver mode)."; \
	fi
  export NUM_JOBS=$(JOBS)

clean:
	rm -rf build/build

sub_submodule: get_jobs
	cd openfoam_source && git submodule update --init --recursive --depth 1

realclean:
	rm -rf build

.PHONY: default install v2112 v2412 deps test sub_submodule clean realclean