-include docs/make-config-default.mk
-include make-config-user.mk

JOBS := $(patsubst -j%,%,$(filter -j%,$(MAKEFLAGS)))
ifeq ($(JOBS),)
  MAKE_PID := $(shell echo $$PPID)
  JOB_FLAG := $(filter -j%, \
    $(subst -j ,-j, \
      $(shell ps -p $(MAKE_PID) -o args= 2>/dev/null \
        | grep -o '\-j[0-9]*')))
  JOBS := $(subst -j,,$(JOB_FLAG))
endif
ifeq ($(JOBS),)
  JOBS := $(BUILD_JOBS)
endif
export NUM_JOBS := $(JOBS)

DOCKER_HOST_ARCH := $(shell uname -m)
ifeq ($(DOCKER_HOST_ARCH),x86_64)
  DOCKER_DEFAULT_PLATFORM := linux/amd64
else ifeq ($(DOCKER_HOST_ARCH),arm64)
  DOCKER_DEFAULT_PLATFORM := linux/arm64
else
  DOCKER_DEFAULT_PLATFORM := linux/amd64
endif

ifeq ($(DOCKER_PLATFORM),)
  ifneq ($(DOCKER_ARCH),)
    DOCKER_PLATFORM := linux/$(DOCKER_ARCH)
  else
    DOCKER_PLATFORM := $(DOCKER_DEFAULT_PLATFORM)
  endif
endif
DOCKER_IMAGE_SUFFIX := $(subst linux/,,$(DOCKER_PLATFORM))

DOCKER_UBUNTU_IMAGE = \
  $(DOCKER_UBUNTU_IMAGE_NAME):$(DOCKER_UBUNTU_VERSION)-$(DOCKER_IMAGE_SUFFIX)
DOCKER_BUILD_IMAGE = \
  $(DOCKER_BUILD_IMAGE_NAME):$(DOCKER_UBUNTU_VERSION)-$(DOCKER_IMAGE_SUFFIX)
DOCKER_OPENFOAM_IMAGE = \
  $(DOCKER_OPENFOAM_IMAGE_NAME):$(DOCKER_UBUNTU_VERSION)-$(DOCKER_IMAGE_SUFFIX)
DOCKER_DIST_BASENAME := $(subst :,-,$(subst /,-,$(DOCKER_OPENFOAM_IMAGE)))
DOCKER_DIST_IMAGE = $(DOCKER_DIST_DIR)/$(DOCKER_DIST_BASENAME).tar.gz

default: get-jobs sync-submodule
	bash install.sh

install: get-jobs sync-submodule
	bash install.sh

v2112: get-jobs sync-submodule
	git checkout v2112
	bash install.sh v2112

v2412: get-jobs sync-submodule
	git checkout v2412
	bash install.sh v2412

deps:
	brew bundle -f

get-jobs:
	@echo "Parallel jobs: $(JOBS)"

clean:
	rm -rf build/docker-dist

sync-submodule:
	git submodule sync
	git submodule update --depth 1 --init

real-clean:
	rm -rf build
	rm -rf openfoam-source
	$(MAKE) sync-submodule

docker-setup-base:
	UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	PLATFORM=$(DOCKER_PLATFORM) ./docker/setup_base_image.sh

docker-setup-build:
	@if docker image inspect "$(DOCKER_BUILD_IMAGE)" >/dev/null 2>&1 \
	    && [ "$(FORCE)" != "1" ]; then \
	  printf '==> %s already exists, skipping docker-setup-build\n' \
	    "$(DOCKER_BUILD_IMAGE)"; \
	else \
	  $(MAKE) docker-setup-base && \
	  DOCKER_BUILDKIT=1 docker buildx build --platform $(DOCKER_PLATFORM) \
	    -f docker/Dockerfile.build \
	    --build-arg DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	    --build-arg UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	    --build-arg APT_MIRROR=$(DOCKER_APT_MIRROR) \
	    -t $(DOCKER_BUILD_IMAGE) \
	    --load .; \
	fi

docker-build: docker-setup-build
	DOCKER_BUILDKIT=1 docker buildx build --platform $(DOCKER_PLATFORM) \
	  -f docker/Dockerfile \
	  --build-arg DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  --build-arg UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  --build-arg NUM_JOBS=$(DOCKER_JOBS) \
	  --build-arg OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  -t $(DOCKER_OPENFOAM_IMAGE) \
	  --load .

docker-cache-status:
	@printf 'OpenFOAM cache id=openfoam-build-%s mount=/cache/openfoam/build/\n' \
	  "$(DOCKER_IMAGE_SUFFIX)"
	@docker buildx du --verbose 2>/dev/null \
	  | rg 'exec.cachemount' -B 5 \
	  | rg 'openfoam-build|Size:|Description:' \
	  || printf '  (none found)\n'

docker-push:
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
	  printf 'DOCKER_REGISTRY is empty; set it in make-config-user.mk\n' \
	    >&2; exit 1; \
	fi
	@remote="$(DOCKER_REGISTRY)/$(DOCKER_OPENFOAM_IMAGE)"; \
	  printf '[docker-push] Tagging %s -> %s\n' \
	    "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker tag "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker push "$$remote"

docker-dist: docker-build
	@mkdir -p "$(DOCKER_DIST_DIR)"
	@printf '[docker-dist] Saving %s -> %s\n' \
	  "$(DOCKER_OPENFOAM_IMAGE)" "$(DOCKER_DIST_IMAGE)"
	@docker save "$(DOCKER_OPENFOAM_IMAGE)" | gzip > "$(DOCKER_DIST_IMAGE)"
	@printf '[docker-dist] Done: %s\n' "$(DOCKER_DIST_IMAGE)"

docker-prune-cache:
	docker builder prune --filter type=exec.cachemount -f

.PHONY: default install v2112 v2412 deps get-jobs sync-submodule clean \
	real-clean docker-setup-base docker-setup-build docker-build \
	docker-push docker-dist docker-prune-cache \
	docker-cache-status
