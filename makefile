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
export OPENFOAM_BUILD := $(OPENFOAM_BUILD)
export OPENFOAM_STAGE := $(OPENFOAM_STAGE)
export OPENFOAM_CLI_BUILD := $(OPENFOAM_CLI_BUILD)
export DOCKER_OPENFOAM_BUILD := $(DOCKER_OPENFOAM_BUILD)
export DOCKER_OPENFOAM_STAGE := $(DOCKER_OPENFOAM_STAGE)
export OPENFOAM_BUILD_MODULES := $(OPENFOAM_BUILD_MODULES)
export OPENFOAM_SYSTEM_CHECK := $(OPENFOAM_SYSTEM_CHECK)
export OPENFOAM_SKIP_ALLWMAKE := $(OPENFOAM_SKIP_ALLWMAKE)
export FORCE := $(FORCE)

.DEFAULT_GOAL := help

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
OPENFOAM_DIST_VERSION := $(patsubst v%,%,$(OPENFOAM_VERSION))
DOCKER_DIST_BASENAME := openfoam-docker-$(OPENFOAM_DIST_VERSION)-linux-$(DOCKER_IMAGE_SUFFIX)
DOCKER_BUILD_IMAGE_TAR = $(BUILD_DOCKER_DIR)/$(DOCKER_DIST_BASENAME).tar.gz
DOCKER_DIST_IMAGE = $(DOCKER_DIST_DIR)/$(DOCKER_DIST_BASENAME).tar.gz

.NOTPARALLEL: openfoam-pack openfoam-dist cli-wheel cli-pack docker-build docker-dist

# =============================================================================
# Build
# =============================================================================

openfoam: get-jobs sync-submodule
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) bash install.sh

cli:
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/install_openfoam_cli.sh "$(CURDIR)/$(OPENFOAM_CLI_BUILD)" "$(CURDIR)/$(OPENFOAM_BUILD)"

all: openfoam cli cli-wheel

check-build:
	@test -f $(OPENFOAM_BUILD)/etc/bashrc || \
	  { echo "Missing $(OPENFOAM_BUILD)/etc/bashrc; run make openfoam first" >&2; exit 1; }

# =============================================================================
# Pack / dist (native openfoam + cli)
# =============================================================================

openfoam-pack: check-build
	@PACK_DIR="$(CURDIR)/$(BUILD_OPENFOAM_PACK_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=0 \
	  bash scripts/openfoam_pack.sh

openfoam-dist: openfoam cli cli-wheel
	@PACK_DIR="$(CURDIR)/$(OPENFOAM_DIST_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=1 \
	  bash scripts/openfoam_pack.sh
	@DIST_DIR="$(CURDIR)/$(OPENFOAM_DIST_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/stage_cli_dist.sh

cli-wheel:
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  BUILD_PY=$(BUILD_PY) \
	  WHEEL_OUT="$(CURDIR)/$(BUILD_CLI_WHEEL_DIR)" \
	  bash scripts/cli_wheel.sh

cli-pack: cli
	@PACK_DIR="$(CURDIR)/$(BUILD_CLI_PACK_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/cli_pack.sh

install:
	@wheel=$$(ls -t "$(BUILD_CLI_WHEEL_DIR)"/$(BUILD_CLI_WHEEL_MATCH) 2>/dev/null | head -1); \
	if [ -z "$$wheel" ]; then \
	  printf 'Wheel not found under %s; run make cli-wheel first\n' \
	    "$(BUILD_CLI_WHEEL_DIR)" >&2; exit 1; fi; \
	printf '[install] %s\n' "$$wheel"; \
	$(BUILD_PY) -m pip install --force-reinstall "$$wheel"

deps:
	brew bundle -f

get-jobs:
	@echo "Parallel jobs: $(JOBS)"

help:
	@echo "OpenFOAM build system ($(OPENFOAM_VERSION), jobs=$(JOBS))"
	@echo ""
	@echo "Top-level:"
	@echo "  make                         show this help"
	@echo "  make openfoam                compile openfoam (-> $(OPENFOAM_BUILD)/)"
	@echo "  make cli                     install cli locally (-> $(OPENFOAM_CLI_BUILD)/bin/)"
	@echo "  make all                     openfoam + cli + cli-wheel"
	@echo "  make install                 pip install CLI wheel"
	@echo "  make all install             all + pip install CLI"
	@echo ""
	@echo "Native openfoam pack:"
	@echo "  make openfoam-pack           tar.gz, no bundle (-> $(BUILD_OPENFOAM_PACK_DIR)/)"
	@echo "  make openfoam-dist           release bundle: native + cli-pack + wheel (-> $(OPENFOAM_DIST_DIR)/)"
	@echo ""
	@echo "CLI pack:"
	@echo "  make cli-wheel               pip wheel (-> $(BUILD_CLI_WHEEL_DIR)/)"
	@echo "  make cli-pack                tar.gz (-> $(BUILD_CLI_PACK_DIR)/)"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build            docker compile + image (-> $(DOCKER_OPENFOAM_BUILD)/ + $(BUILD_DOCKER_DIR)/)"
	@echo "  make docker-dist             release bundle: image + cli-pack + wheel (-> $(DOCKER_DIST_DIR)/)"
	@echo "  make docker-setup-base       pull $(DOCKER_UBUNTU_IMAGE)"
	@echo "  make docker-setup-build      build $(DOCKER_BUILD_IMAGE)"
	@echo "  make docker-push             push image (set DOCKER_REGISTRY)"
	@echo "  make docker-prune-images     docker image prune -f"
	@echo ""
	@echo "Other:"
	@echo "  make deps                    Homebrew dependencies (macOS)"
	@echo "  FORCE=1 make openfoam        re-run Allwmake even if source unchanged"
	@echo "  Version: set OPENFOAM_VERSION in make-config-user.mk (default $(OPENFOAM_VERSION))"
	@echo ""
	@echo "Clean:"
	@echo "  make clean                   remove build/"
	@echo "  make real-clean              clean + reset openfoam-source"
	@echo ""
	@echo "After make all:"
	@echo "  source $(OPENFOAM_BUILD)/etc/bashrc"
	@echo "  export PATH=\"$(CURDIR)/$(OPENFOAM_CLI_BUILD)/bin:\$$PATH\""
	@echo ""
	@echo "Config: docs/make-config-default.mk, make-config-user.mk"

# --- Clean / submodule ---

clean:
	rm -rf build

sync-submodule:
	git -c submodule.recurse=false submodule sync -- openfoam-source
	git -c submodule.recurse=false submodule update --init --depth 1 -- openfoam-source

real-clean: clean
	@if [ -d openfoam-source ]; then \
	  chflags -R nouchg openfoam-source 2>/dev/null; \
	  chmod -R u+w openfoam-source 2>/dev/null; \
	  find openfoam-source -name .DS_Store -delete 2>/dev/null; \
	  rm -rf openfoam-source || { \
	    find openfoam-source -mindepth 1 -delete 2>/dev/null; \
	    rm -rf openfoam-source; \
	  }; \
	fi
	@test ! -d openfoam-source
	git checkout openfoam-source
	$(MAKE) sync-submodule

# --- Docker ---

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
	  DOCKER_BUILD_IMAGE=$(DOCKER_BUILD_IMAGE) \
	  DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_DOCKERFILE=docker/Dockerfile \
	  DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  DOCKER_OPENFOAM_BUILD=$(DOCKER_OPENFOAM_BUILD) \
	  DOCKER_OPENFOAM_STAGE=$(DOCKER_OPENFOAM_STAGE) \
	  OPENFOAM_RUNTIME_DEPS_REV=$(OPENFOAM_RUNTIME_DEPS_REV) \
	  DOCKER_JOBS=$(DOCKER_JOBS) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUILD_MODULES=$(OPENFOAM_BUILD_MODULES) \
	  FORCE=$(FORCE) \
	  bash docker/setup_openfoam_image.sh
	@mkdir -p "$(BUILD_DOCKER_DIR)"
	@printf '[docker-build] Saving %s -> %s\n' \
	  "$(DOCKER_OPENFOAM_IMAGE)" "$(DOCKER_BUILD_IMAGE_TAR)"
	@docker save "$(DOCKER_OPENFOAM_IMAGE)" | gzip > "$(DOCKER_BUILD_IMAGE_TAR)"

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

docker-dist: docker-build cli cli-wheel
	@mkdir -p "$(DOCKER_DIST_DIR)"
	@printf '[docker-dist] Exporting %s -> %s\n' \
	  "$(DOCKER_BUILD_IMAGE_TAR)" "$(DOCKER_DIST_IMAGE)"
	@cp "$(DOCKER_BUILD_IMAGE_TAR)" "$(DOCKER_DIST_IMAGE)"
	@DIST_DIR="$(CURDIR)/$(DOCKER_DIST_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/stage_cli_dist.sh
	@printf '[docker-dist] Done (%s)\n' "$(DOCKER_DIST_DIR)/"

docker-prune-images:
	@docker image prune -f

.PHONY: help openfoam cli all install get-jobs deps sync-submodule clean real-clean \
	check-build \
	openfoam-pack openfoam-dist \
	cli-wheel cli-pack \
	docker-setup-base docker-setup-build docker-build docker-push docker-dist \
	docker-prune-images
