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
export OPENFOAM_BUILD_MODULES := $(OPENFOAM_BUILD_MODULES)
export OPENFOAM_SYSTEM_CHECK := $(OPENFOAM_SYSTEM_CHECK)
export OPENFOAM_SKIP_ALLWMAKE := $(OPENFOAM_SKIP_ALLWMAKE)
export FORCE := $(FORCE)

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

# wheel/cpack/docker pipelines must not run in parallel with -j.
.NOTPARALLEL: wheel wheel-dist cpack cpack-dist docker-build docker-dist cli

default: get-jobs sync-submodule
	bash install.sh

ifeq ($(filter wheel install,$(MAKECMDGOALS)),wheel install)
install: wheel-install
else
install: get-jobs sync-submodule
	bash install.sh
endif

check-build:
	@test -f build/etc/bashrc || \
	  { echo "Missing build/etc/bashrc; run make install first" >&2; exit 1; }

wheel: check-build
	@INCLUDE_NATIVE=1 OPENFOAM_WHEEL_DIR=$(BUILD_WHEEL_DIR) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  BUILD_PY=$(BUILD_PY) \
	  OPENFOAM_BUNDLE_RUNTIME=0 \
	  bash scripts/openfoam_wheel.sh

wheel-dist: check-build
	@INCLUDE_NATIVE=1 OPENFOAM_WHEEL_DIR=$(BUILD_WHEEL_DIST_DIR) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  BUILD_PY=$(BUILD_PY) \
	  OPENFOAM_BUNDLE_RUNTIME=1 \
	  bash scripts/openfoam_wheel.sh

wheel-install: wheel
	@wheel=$$(ls "$(BUILD_WHEEL_DIR)"/$(BUILD_WHEEL_MATCH) 2>/dev/null | tail -1); \
	if [ -z "$$wheel" ]; then \
	  printf 'Wheel not found under %s; run make wheel first\n' \
	    "$(BUILD_WHEEL_DIR)" >&2; exit 1; fi; \
	printf '[wheel-install] %s\n' "$$wheel"; \
	$(BUILD_PY) -m pip install --force-reinstall "$$wheel"

cpack: check-build
	@CPACK_DIR="$(CURDIR)/$(BUILD_CPACK_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=0 \
	  bash scripts/openfoam_cpack.sh

cpack-dist: check-build
	@CPACK_DIR="$(CURDIR)/$(BUILD_CPACK_DIST_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=1 \
	  bash scripts/openfoam_cpack.sh

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

help:
	@echo "OpenFOAM build system"
	@echo ""
	@echo "Native build:"
	@echo "  make / install / v2112 / v2412   Compile into build/"
	@echo "  FORCE=1 make install               Force Allwmake even if source unchanged"
	@echo ""
	@echo "Distribution:"
	@echo "  make wheel                       Pack native wheel + CLI (-> $(BUILD_WHEEL_DIR)/)"
	@echo "  make wheel-install               wheel + pip install (local, no dylib bundle)"
	@echo "  make wheel install               same as wheel-install"
	@echo "  make wheel-dist                  Distributable wheel + bundled dylibs (-> $(BUILD_WHEEL_DIST_DIR)/)"
	@echo "  make cpack                       Native tar.gz + bin/openfoam (-> $(BUILD_CPACK_DIR)/)"
	@echo "  make cpack-dist                  Distributable tar.gz + bundled dylibs (-> $(BUILD_CPACK_DIST_DIR)/)"
	@echo "  make docker-dist                 Docker image + CLI wheel (-> $(DOCKER_DIST_DIR)/)"
	@echo "  make cli-install                 CLI-only wheel from docker-dist"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-setup-base / docker-setup-build / docker-build"
	@echo "  make docker-push                 Push openfoam image (DOCKER_REGISTRY)"
	@echo ""
	@echo "Clean:"
	@echo "  make clean                       Remove dist/stage only (keeps build/ compile tree)"
	@echo "  make real-clean                  Remove build/ and re-sync submodules"
	@echo ""
	@echo "CLI (after install or pip install openfoam-*.whl):"
	@echo "  openfoam case ~/case             Run Allrun (native)"
	@echo "  openfoam env                     Print source .../etc/bashrc (for wmake/cmake)"
	@echo "  openfoam docker-run ...          Run in Docker"
	@echo ""
	@echo "Config: docs/make-config-default.mk, make-config-user.mk"

clean:
	rm -rf build/docker-dist build/wheel build/wheel-dist \
	  build/cpack build/cpack-dist build/stage build/openfoam-wheel

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

docker-setup-build: docker-setup-base
	@DOCKER_BUILD_IMAGE=$(DOCKER_BUILD_IMAGE) \
	  DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_DOCKERFILE_BUILD=docker/Dockerfile.build \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  PHYNEXIS_BUILD_DEPS_REV=$(PHYNEXIS_BUILD_DEPS_REV) \
	  FORCE=$(FORCE) \
	  bash docker/setup_build_image.sh

docker-build: sync-submodule docker-setup-build
	@DOCKER_OPENFOAM_IMAGE=$(DOCKER_OPENFOAM_IMAGE) \
	  DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_DOCKERFILE=docker/Dockerfile \
	  DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  OPENFOAM_RUNTIME_DEPS_REV=$(OPENFOAM_RUNTIME_DEPS_REV) \
	  DOCKER_JOBS=$(DOCKER_JOBS) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUILD_MODULES=$(OPENFOAM_BUILD_MODULES) \
	  FORCE=$(FORCE) \
	  bash docker/setup_openfoam_image.sh

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

docker-dist: docker-build cli
	@mkdir -p "$(DOCKER_DIST_DIR)"
	@printf '[docker-dist] Saving %s -> %s\n' \
	  "$(DOCKER_OPENFOAM_IMAGE)" "$(DOCKER_DIST_IMAGE)"
	@docker save "$(DOCKER_OPENFOAM_IMAGE)" | gzip > "$(DOCKER_DIST_IMAGE)"
	@printf '[docker-dist] Done (%s + openfoam-*.whl in %s)\n' \
	  "$(DOCKER_DIST_IMAGE)" "$(DOCKER_DIST_DIR)"

# CLI-only wheel for docker channel (-> $(DOCKER_DIST_DIR)/openfoam-*.whl)
cli:
	@INCLUDE_NATIVE=0 DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  bash scripts/openfoam_wheel.sh

cli-install: cli
	@wheel=$$(ls "$(DOCKER_DIST_DIR)"/openfoam-*.whl 2>/dev/null | tail -1); \
	if [ -z "$$wheel" ]; then \
	  printf 'Wheel not found under %s; run make cli first\n' \
	    "$(DOCKER_DIST_DIR)" >&2; exit 1; fi; \
	printf '[cli-install] %s\n' "$$wheel"; \
	python3 -m pip install --force-reinstall "$$wheel"

docker-prune-cache:
	docker builder prune --filter type=exec.cachemount -f

docker-prune-images:
	@docker image prune -f

.PHONY: default install v2112 v2412 deps get-jobs help sync-submodule clean \
	check-build wheel wheel-dist wheel-install cpack cpack-dist \
	real-clean docker-setup-base docker-setup-build docker-build \
	docker-push docker-dist cli cli-install docker-prune-cache docker-prune-images \
	docker-cache-status
