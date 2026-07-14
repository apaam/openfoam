-include docs/make-config-default.mk
-include make-config-user.mk

# Host trees before CONTAINER_BUILD remapping.
HOST_BUILD_ROOT := $(BUILD_ROOT)
HOST_INSTALL_PREFIX := $(INSTALL_PREFIX)

# docker-shell: BUILD_ROOT → DOCKER_BUILD_ROOT; re-derive paths.
ifeq ($(CONTAINER_BUILD),1)
  BUILD_ROOT := $(DOCKER_BUILD_ROOT)
  INSTALL_PREFIX := $(DOCKER_INSTALL_PREFIX)
  OPENFOAM_BUILD := $(BUILD_ROOT)/openfoam-build
  OPENFOAM_CLI_BUILD := $(BUILD_ROOT)/cli-build
  OPENFOAM_STAGE := $(BUILD_ROOT)/stage/pack
  BUILD_PACK_DIR := $(BUILD_ROOT)/pack
  BUILD_WHEEL_DIR := $(BUILD_ROOT)/wheel
  DIST_NATIVE_DIR := $(BUILD_ROOT)/dist-native
  DIST_DOCKER_DIR := $(BUILD_ROOT)/dist-docker
  BUILD_DOCKER_DIR := $(BUILD_ROOT)/docker
  BUILD_WHEEL_STAGE_DIR := $(BUILD_ROOT)/stage/cli-wheel
  BUILD_WHEEL_TMP_DIR := $(BUILD_ROOT)/stage/wheel-build
endif

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
export CONTAINER_BUILD
export BUILD_ROOT := $(BUILD_ROOT)
export DOCKER_BUILD_ROOT := $(DOCKER_BUILD_ROOT)
export OPENFOAM_BUILD := $(OPENFOAM_BUILD)
export OPENFOAM_STAGE := $(OPENFOAM_STAGE)
export OPENFOAM_CLI_BUILD := $(OPENFOAM_CLI_BUILD)
export BUILD_PACK_DIR := $(BUILD_PACK_DIR)
export BUILD_WHEEL_DIR := $(BUILD_WHEEL_DIR)
export DIST_NATIVE_DIR := $(DIST_NATIVE_DIR)
export DIST_DOCKER_DIR := $(DIST_DOCKER_DIR)
export BUILD_DOCKER_DIR := $(BUILD_DOCKER_DIR)
export BUILD_WHEEL_STAGE_DIR := $(BUILD_WHEEL_STAGE_DIR)
export BUILD_WHEEL_TMP_DIR := $(BUILD_WHEEL_TMP_DIR)
export BUILD_WHEEL_MATCH := $(BUILD_WHEEL_MATCH)
export OPENFOAM_BUILD_MODULES := $(OPENFOAM_BUILD_MODULES)
export OPENFOAM_SYSTEM_CHECK := $(OPENFOAM_SYSTEM_CHECK)
export OPENFOAM_SKIP_ALLWMAKE := $(OPENFOAM_SKIP_ALLWMAKE)
export FORCE := $(FORCE)
export INSTALL_PREFIX := $(INSTALL_PREFIX)
export DOCKER_INSTALL_PREFIX := $(DOCKER_INSTALL_PREFIX)

.DEFAULT_GOAL := help

DOCKER_HOST_ARCH := $(shell uname -m)
ifeq ($(DOCKER_HOST_ARCH),x86_64)
  DOCKER_DEFAULT_PLATFORM := linux/amd64
else ifneq ($(filter arm64 aarch64,$(DOCKER_HOST_ARCH)),)
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
DOCKER_IMAGE_TAR = $(BUILD_DOCKER_DIR)/$(DOCKER_DIST_BASENAME).tar.gz

.NOTPARALLEL: pack wheel dist-native \
	_docker-pack-image dist-docker docker-dist-native docker-dist-docker \
	install all-install

# =============================================================================
# Build
# =============================================================================

openfoam: get-jobs sync-submodule
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) bash install.sh

cli:
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/install_openfoam_cli.sh \
	    "$(CURDIR)/$(OPENFOAM_CLI_BUILD)" "$(CURDIR)/$(OPENFOAM_BUILD)"

all: openfoam cli

check-build:
	@test -f $(OPENFOAM_BUILD)/etc/bashrc || \
	  { echo "Missing $(OPENFOAM_BUILD)/etc/bashrc; run make openfoam first" >&2; exit 1; }

# =============================================================================
# Package (peer forms: pack | wheel)
# =============================================================================

pack: all
	@PACK_DIR="$(CURDIR)/$(BUILD_PACK_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=0 \
	  bash scripts/openfoam_pack.sh

wheel: cli
	@OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  BUILD_PY=$(BUILD_PY) \
	  WHEEL_OUT="$(CURDIR)/$(BUILD_WHEEL_DIR)" \
	  bash scripts/cli_wheel.sh

# =============================================================================
# Install
# =============================================================================

install: check-build
	@INSTALL_PREFIX="$(INSTALL_PREFIX)" \
	  OPENFOAM_BUNDLE_RUNTIME=0 \
	  bash scripts/install_openfoam_prefix.sh

all-install: all install

# =============================================================================
# Dist
# =============================================================================

dist-native: all wheel
	@PACK_DIR="$(CURDIR)/$(DIST_NATIVE_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  OPENFOAM_BUNDLE_RUNTIME=1 \
	  bash scripts/openfoam_pack.sh
	@DIST_DIR="$(CURDIR)/$(DIST_NATIVE_DIR)" \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash scripts/stage_cli_dist.sh

deps:
	@bash scripts/install_deps.sh

get-jobs:
	@echo "Parallel jobs: $(JOBS)"

help:
	@echo "OpenFOAM build system ($(OPENFOAM_VERSION), jobs=$(JOBS))"
	@echo ""
	@echo "Build:"
	@echo "  make openfoam                -> $(OPENFOAM_BUILD)/"
	@echo "  make cli                     -> $(OPENFOAM_CLI_BUILD)/"
	@echo "  make all                     openfoam + cli"
	@echo ""
	@echo "Package:"
	@echo "  make pack                    one tar (OF+CLI) -> $(BUILD_PACK_DIR)/"
	@echo "  make wheel                   one whl -> $(BUILD_WHEEL_DIR)/"
	@echo ""
	@echo "Install:"
	@echo "  make install                 build -> $(HOST_INSTALL_PREFIX)/ (no pack/wheel)"
	@echo "  make all-install             all + install"
	@echo ""
	@echo "Dist:"
	@echo "  make dist-native             bundled tar + whl -> $(DIST_NATIVE_DIR)/"
	@echo "  make dist-docker             Linux: image + host CLI pack/whl -> $(HOST_BUILD_ROOT)/dist-docker/"
	@echo ""
	@echo "Docker (host only):"
	@echo "  make docker-shell            -> $(DOCKER_BUILD_ROOT)/"
	@echo "  make docker-dist-native      container dist-native -> $(DOCKER_BUILD_ROOT)/"
	@echo "  make docker-dist-docker      image + host CLI -> $(DOCKER_BUILD_ROOT)/dist-docker/"
	@echo "  make docker-setup-base / docker-setup-build / docker-push / docker-prune-images"
	@echo ""
	@echo "Clean:"
	@echo "  make clean-build             remove $(HOST_BUILD_ROOT)/"
	@echo "  make clean-docker-build      remove $(DOCKER_BUILD_ROOT)/"
	@echo "  make clean-install           remove $(HOST_INSTALL_PREFIX)/"
	@echo "  make clean-docker-install    remove $(DOCKER_INSTALL_PREFIX)/"
	@echo "  make clean-submodules        reset openfoam-source"
	@echo ""
	@echo "After make all:"
	@echo "  source $(OPENFOAM_BUILD)/etc/bashrc"
	@echo "  export PATH=\"$(CURDIR)/$(OPENFOAM_CLI_BUILD)/bin:\$$PATH\""
	@echo ""
	@echo "After make all-install:"
	@echo "  export OPENFOAM_PREFIX=$(CURDIR)/$(HOST_INSTALL_PREFIX)"
	@echo "  source \"\$$OPENFOAM_PREFIX/etc/bashrc\""
	@echo ""
	@echo "Config: BUILD_ROOT=$(BUILD_ROOT) INSTALL_PREFIX=$(HOST_INSTALL_PREFIX)"
	@echo "        docker: $(DOCKER_BUILD_ROOT) / $(DOCKER_INSTALL_PREFIX)"

# --- Clean / submodule ---

clean-build:
	@case "$(HOST_BUILD_ROOT)" in \
	  ""|"."|".."|"/"|*..*) \
	    echo "Refusing to clean HOST_BUILD_ROOT='$(HOST_BUILD_ROOT)'" >&2; \
	    exit 1 ;; \
	esac; \
	rm -rf -- "$(HOST_BUILD_ROOT)" 2>/dev/null || true; \
	rm -rf -- "$(HOST_BUILD_ROOT)"

clean-docker-build:
	@case "$(DOCKER_BUILD_ROOT)" in \
	  ""|"."|".."|"/"|*..*) \
	    echo "Refusing to clean DOCKER_BUILD_ROOT='$(DOCKER_BUILD_ROOT)'" >&2; \
	    exit 1 ;; \
	esac; \
	rm -rf -- "$(DOCKER_BUILD_ROOT)" 2>/dev/null || true; \
	rm -rf -- "$(DOCKER_BUILD_ROOT)"

clean-install:
	@case "$(HOST_INSTALL_PREFIX)" in \
	  ""|"."|".."|"/"|*..*) \
	    echo "Refusing to clean HOST_INSTALL_PREFIX='$(HOST_INSTALL_PREFIX)'" >&2; \
	    exit 1 ;; \
	esac; \
	rm -rf -- "$(HOST_INSTALL_PREFIX)" 2>/dev/null || true; \
	rm -rf -- "$(HOST_INSTALL_PREFIX)"

clean-docker-install:
	@case "$(DOCKER_INSTALL_PREFIX)" in \
	  ""|"."|".."|"/"|*..*) \
	    echo "Refusing to clean DOCKER_INSTALL_PREFIX='$(DOCKER_INSTALL_PREFIX)'" >&2; \
	    exit 1 ;; \
	esac; \
	rm -rf -- "$(DOCKER_INSTALL_PREFIX)" 2>/dev/null || true; \
	rm -rf -- "$(DOCKER_INSTALL_PREFIX)"

clean-submodules:
	@if [ -d openfoam-source ]; then \
	  chflags -R nouchg openfoam-source 2>/dev/null; \
	  chmod -R u+w openfoam-source 2>/dev/null; \
	  rm -rf openfoam-source 2>/dev/null || true; \
	  rm -rf openfoam-source; \
	fi
	@test ! -d openfoam-source
	git checkout openfoam-source
	$(MAKE) sync-submodule

sync-submodule:
	git -c submodule.recurse=false submodule sync -- openfoam-source
	git -c submodule.recurse=false submodule update --init --depth 1 -- openfoam-source

# --- Docker ---

docker-host-guard:
	@if [ -f /.dockerenv ] || [ "$(CURDIR)" = "/src" ]; then \
	  printf 'Refuse: docker-* must run on the host, not inside docker-shell.\n' \
	    >&2; \
	  exit 1; \
	fi

docker-setup-build: docker-host-guard
	@DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  FORCE=$(FORCE) \
	  bash docker/setup_build_image.sh

docker-shell: docker-host-guard
	@DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  BUILD_JOBS=$(JOBS) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  bash docker/build_in_container.sh

docker-setup-base: docker-host-guard
	UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	PLATFORM=$(DOCKER_PLATFORM) ./docker/setup_base_image.sh

_docker-pack-image: docker-host-guard
	@DOCKER_OPENFOAM_IMAGE=$(DOCKER_OPENFOAM_IMAGE) \
	  DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_UBUNTU_IMAGE_NAME=$(DOCKER_UBUNTU_IMAGE_NAME) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  DIST_NATIVE_DIR=$(DIST_NATIVE_DIR) \
	  BUILD_DOCKER_DIR=$(BUILD_DOCKER_DIR) \
	  DOCKER_IMAGE_TAR="$(CURDIR)/$(DOCKER_IMAGE_TAR)" \
	  OPENFOAM_NATIVE_DIST="$(OPENFOAM_NATIVE_DIST)" \
	  bash docker/setup_openfoam_image.sh

# Export image + host CLI pack + wheel into $(1)/dist-docker/.
# $(2) is CONTAINER_BUILD when rebuilding CLI from that tree.
define _dist-docker-export
img_tar="$(1)/docker/$(DOCKER_DIST_BASENAME).tar.gz"; \
if [ ! -f "$$img_tar" ]; then \
  printf '[dist-docker] Missing %s (need linux native under %s/dist-native/)\n' \
    "$$img_tar" "$(1)" >&2; \
  exit 1; \
fi; \
mkdir -p "$(1)/dist-docker"; \
printf '[dist-docker] Exporting %s -> %s/dist-docker/\n' \
  "$$img_tar" "$(1)"; \
cp "$$img_tar" "$(1)/dist-docker/$(DOCKER_DIST_BASENAME).tar.gz"; \
$(MAKE) CONTAINER_BUILD=$(2) BUILD_ROOT=$(1) cli wheel; \
DIST_DIR="$(CURDIR)/$(1)/dist-docker" \
  HOST_CLI_PACK=1 \
  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
  bash scripts/stage_cli_dist.sh; \
printf '[dist-docker] Done (%s/dist-docker/)\n' "$(1)"
endef

dist-docker:
ifeq ($(shell uname -s),Darwin)
	@printf 'dist-docker packs host linux native into a Linux image.\n' >&2
	@printf 'On macOS use: make docker-dist-docker\n' >&2
else
	@$(MAKE) docker-host-guard
	@$(MAKE) CONTAINER_BUILD= BUILD_ROOT=$(HOST_BUILD_ROOT) _docker-pack-image
	@$(call _dist-docker-export,$(HOST_BUILD_ROOT),)
endif

_docker-compile: docker-host-guard
	@DOCKER_PLATFORM=$(DOCKER_PLATFORM) \
	  DOCKER_UBUNTU_VERSION=$(DOCKER_UBUNTU_VERSION) \
	  DOCKER_BUILD_IMAGE_NAME=$(DOCKER_BUILD_IMAGE_NAME) \
	  DOCKER_APT_MIRROR=$(DOCKER_APT_MIRROR) \
	  BUILD_JOBS=$(JOBS) \
	  OPENFOAM_VERSION=$(OPENFOAM_VERSION) \
	  FORCE=$(FORCE) \
	  bash docker/compile_openfoam.sh

docker-dist-native: _docker-compile
	@printf '[docker-dist-native] Done (%s/dist-native/)\n' "$(DOCKER_BUILD_ROOT)"

docker-dist-docker: _docker-compile
	@$(MAKE) CONTAINER_BUILD=1 _docker-pack-image
	@$(call _dist-docker-export,$(DOCKER_BUILD_ROOT),1)

docker-push: docker-host-guard
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
	  printf 'DOCKER_REGISTRY is empty; set it in make-config-user.mk\n' \
	    >&2; exit 1; \
	fi
	@docker image inspect "$(DOCKER_OPENFOAM_IMAGE)" >/dev/null 2>&1 || { \
	  printf 'Missing %s; run make docker-dist-docker (or dist-docker) first\n' \
	    "$(DOCKER_OPENFOAM_IMAGE)" >&2; \
	  exit 1; \
	}
	@remote="$(DOCKER_REGISTRY)/$(DOCKER_OPENFOAM_IMAGE)"; \
	  printf '[docker-push] Tagging %s -> %s\n' \
	    "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker tag "$(DOCKER_OPENFOAM_IMAGE)" "$$remote"; \
	  docker push "$$remote"

docker-prune-images:
	@docker image prune -f

.PHONY: help openfoam cli all pack wheel install all-install \
	get-jobs deps sync-submodule \
	clean-build clean-docker-build clean-install clean-docker-install \
	clean-submodules check-build \
	dist-native dist-docker \
	docker-host-guard docker-setup-build docker-shell \
	docker-setup-base _docker-pack-image docker-push \
	_docker-compile docker-dist-native docker-dist-docker \
	docker-prune-images
