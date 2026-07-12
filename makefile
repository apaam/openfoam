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
export OPENFOAM_CLI_BUILD := $(OPENFOAM_CLI_BUILD)
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

# --- Native compile (install tree -> $(OPENFOAM_BUILD)/) ---

default: get-jobs sync-submodule
	bash install.sh

ifeq ($(filter wheel install,$(MAKECMDGOALS)),wheel install)
install: wheel-install
else
install: get-jobs sync-submodule
	bash install.sh
endif

check-build:
	@test -f $(OPENFOAM_BUILD)/etc/bashrc || \
	  { echo "Missing $(OPENFOAM_BUILD)/etc/bashrc; run make install first" >&2; exit 1; }

install-cli: check-build
	@bash scripts/install_openfoam_cli.sh "$(CURDIR)/$(OPENFOAM_CLI_BUILD)" "$(CURDIR)/$(OPENFOAM_BUILD)"

# --- Distribution (requires check-build; uses $(OPENFOAM_BUILD)/, no recompile) ---

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
	@wheel=$$(ls -t "$(BUILD_WHEEL_DIR)"/$(BUILD_WHEEL_MATCH) 2>/dev/null | head -1); \
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

# --- Version switch (git checkout + full install) ---

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
	@echo "OpenFOAM build system ($(OPENFOAM_VERSION), jobs=$(JOBS))"
	@echo ""
	@echo "Layout:"
	@echo "  $(OPENFOAM_BUILD)/          WM_PROJECT_DIR (compile + install)"
	@echo "  $(OPENFOAM_CLI_BUILD)/           openfoam CLI (local install)"
	@echo "  build/stage/ build/wheel/ ...  packaging workspace (see make-config-default.mk)"
	@echo ""
	@echo "Native compile:"
	@echo "  make, install              Build $(OPENFOAM_BUILD)/ + CLI -> $(OPENFOAM_CLI_BUILD)/"
	@echo "  make install-cli           Refresh CLI only (-> $(OPENFOAM_CLI_BUILD)/)"
	@echo "  make v2112, make v2412     Checkout version branch, then install"
	@echo "  make deps                  Homebrew dependencies (macOS)"
	@echo "  FORCE=1 make install       Re-run Allwmake even if source unchanged"
	@echo ""
	@echo "Distribution (needs $(OPENFOAM_BUILD)/etc/bashrc):"
	@echo "  make wheel                 Wheel + CLI, local dylibs (-> $(BUILD_WHEEL_DIR)/)"
	@echo "  make wheel-install         wheel + pip install --force-reinstall"
	@echo "  make wheel install         same as wheel-install"
	@echo "  make wheel-dist            Wheel + CLI, bundled dylibs (-> $(BUILD_WHEEL_DIST_DIR)/)"
	@echo "  make cpack                 tar.gz + bin/openfoam (-> $(BUILD_CPACK_DIR)/)"
	@echo "  make cpack-dist            tar.gz + bundled dylibs (-> $(BUILD_CPACK_DIST_DIR)/)"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-setup-base     Pull $(DOCKER_UBUNTU_IMAGE)"
	@echo "  make docker-setup-build    Build $(DOCKER_BUILD_IMAGE)"
	@echo "  make docker-build          Build $(DOCKER_OPENFOAM_IMAGE)"
	@echo "  make docker-dist           docker-build + save image + CLI wheel (-> $(DOCKER_DIST_DIR)/)"
	@echo "  make cli                   CLI-only wheel (-> $(DOCKER_DIST_DIR)/)"
	@echo "  make cli-install           cli + pip install"
	@echo "  make docker-push           Push image (set DOCKER_REGISTRY)"
	@echo "  make docker-cache-status   Show buildx cache mount usage"
	@echo "  make docker-prune-cache    Prune exec.cachemount build cache"
	@echo "  make docker-prune-images   docker image prune -f"
	@echo ""
	@echo "Clean:"
	@echo "  make clean                 Remove build/ (compile cache + packaging)"
	@echo "  make real-clean            clean + reset openfoam-source + sync-submodule"
	@echo ""
	@echo "After make install:"
	@echo "  source \$(OPENFOAM_BUILD)/etc/bashrc"
	@echo "  export PATH=\"\$(OPENFOAM_CLI_BUILD)/bin:\$\$PATH\""
	@echo "After pip install openfoam-*.whl:"
	@echo "  export OPENFOAM_PREFIX=/opt/openfoam   # optional; this is the default"
	@echo "  openfoam dev install"
	@echo "  source \"\$\$OPENFOAM_PREFIX/etc/bashrc\""
	@echo "  openfoam run ~/case/Allrun"
	@echo ""
	@echo "openfoam CLI (openfoam help):"
	@echo "  prefix dev install|clean completion run shell"
	@echo "  docker pull|install-image|uninstall-image|run|shell"
	@echo ""
	@echo "Config: docs/make-config-default.mk, make-config-user.mk"

# --- Clean / submodule ---

clean:
	rm -rf build

sync-submodule:
	git submodule sync
	git submodule update --depth 1 --init

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

# --- Docker images ---

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
	@printf 'OpenFOAM cache id=openfoam-build-%s mount=/cache/openfoam/$(OPENFOAM_BUILD)/\n' \
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
	@wheel=$$(ls -t "$(DOCKER_DIST_DIR)"/openfoam-*.whl 2>/dev/null | head -1); \
	if [ -z "$$wheel" ]; then \
	  printf 'Wheel not found under %s; run make cli first\n' \
	    "$(DOCKER_DIST_DIR)" >&2; exit 1; fi; \
	printf '[cli-install] %s\n' "$$wheel"; \
	python3 -m pip install --force-reinstall "$$wheel"

docker-prune-cache:
	docker builder prune --filter type=exec.cachemount -f

docker-prune-images:
	@docker image prune -f

.PHONY: default install help get-jobs deps sync-submodule clean real-clean \
	check-build v2112 v2412 install-cli wheel wheel-dist wheel-install cpack cpack-dist \
	docker-setup-base docker-setup-build docker-build docker-push docker-dist \
	cli cli-install docker-cache-status docker-prune-cache docker-prune-images
