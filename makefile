MAKE_PID := $(shell echo $$PPID)
JOB_FLAG := $(filter -j%, $(subst -j ,-j,$(shell ps T | grep "^\s*$(MAKE_PID).*$(MAKE)")))
JOBS     := $(subst -j,,$(JOB_FLAG))
ifneq ($(JOBS),)
export NUM_JOBS := $(JOBS)
endif

DOCKER_HOST_ARCH := $(shell uname -m)
ifeq ($(DOCKER_HOST_ARCH),x86_64)
  DOCKER_DEFAULT_PLATFORM := linux/amd64
else ifeq ($(DOCKER_HOST_ARCH),arm64)
  DOCKER_DEFAULT_PLATFORM := linux/arm64
else
  DOCKER_DEFAULT_PLATFORM := linux/amd64
endif

ifneq ($(DOCKER_ARCH),)
  DOCKER_PLATFORM := linux/$(DOCKER_ARCH)
endif
DOCKER_PLATFORM ?= $(DOCKER_DEFAULT_PLATFORM)
DOCKER_IMAGE_SUFFIX := $(subst linux/,,$(DOCKER_PLATFORM))

DOCKER_UBUNTU_VERSION ?= 24.04
DOCKER_BUILD_IMAGE_NAME ?= phynexis-build
DOCKER_IMAGE_NAME ?= openfoam
DOCKER_JOBS ?= 4
OPENFOAM_VERSION ?= v2412
DOCKER_OPENFOAM_IMAGE = $(DOCKER_IMAGE_NAME):$(DOCKER_UBUNTU_VERSION)-$(DOCKER_IMAGE_SUFFIX)

default: get_jobs sync_submodule
	bash install.sh

install: get_jobs sync_submodule
	bash install.sh

v2112: get_jobs sync_submodule
	git checkout v2112
	bash install.sh v2112

v2412: get_jobs sync_submodule
	git checkout v2412
	bash install.sh v2412

deps:
	brew bundle -f

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

clean:
	rm -rf build/build

sync_submodule:
	git submodule sync
	git submodule update --depth 1 --init

realclean:
	rm -rf build
	rm -rf openfoam-source
	make sync_submodule

docker-build:
	@docker image inspect "$(DOCKER_BUILD_IMAGE_NAME):$(DOCKER_UBUNTU_VERSION)-$(DOCKER_IMAGE_SUFFIX)" >/dev/null 2>&1 \
	  || { printf 'Missing phynexis-build image; run docker-setup-build in phynexis-v0 first\n' >&2; exit 1; }
	DOCKER_BUILDKIT=1 docker buildx build --platform $(DOCKER_PLATFORM) \
	  -f docker/Dockerfile \
	  --build-arg DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  --build-arg UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  --build-arg NUM_JOBS=$(DOCKER_JOBS) \
	  --build-arg OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  -t $(DOCKER_OPENFOAM_IMAGE) \
	  --load .

docker-push:
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
	  printf 'DOCKER_REGISTRY is empty; set it when invoking make\n' >&2; exit 1; \
	fi
	@remote="$(DOCKER_REGISTRY)/$(DOCKER_OPENFOAM_IMAGE)"; \
	  printf '[docker-push] Tagging %s -> %s\n' "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker tag "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker push "$$remote"

.PHONY: default install v2112 v2412 deps test sync_submodule clean realclean docker-build docker-push