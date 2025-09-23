MAKE_PID := $(shell echo $$PPID)
JOB_FLAG := $(filter -j%, $(subst -j ,-j,$(shell ps T | grep "^\s*$(MAKE_PID).*$(MAKE)")))
JOBS     := $(subst -j,,$(JOB_FLAG))

default: get_jobs
	bash install_v2412.sh

v2112: get_jobs
	bash install_v2112.sh

v2412: get_jobs
	bash install_v2412.sh

deps_v2112:
	brew bundle --file=Brewfile_v2112

deps_v2412:
	brew bundle --file=Brewfile_v2412

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
	rm -rf v2112_build/build v2412_build/build

realclean:
	rm -rf v2112_build v2412_build

.PHONY: default v2112 v2412 deps_v2112 deps_v2412 test clean realclean




