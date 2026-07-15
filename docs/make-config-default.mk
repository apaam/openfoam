# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).
#
# Path model:
#   BUILD_ROOT / DOCKER_BUILD_ROOT — build trees (components + pack/wheel/dist)
#   INSTALL_PREFIX / DOCKER_INSTALL_PREFIX — make install from build (not pack/wheel)
#   Components live under openfoam-build/ and cli-build/
#
# Prefer changing BUILD_ROOT / DOCKER_BUILD_ROOT; keep derived paths as $(BUILD_ROOT)/...

# --- Native build ---
BUILD_JOBS = 2
BUILD_PY = python3
OPENFOAM_VERSION = v2412

BUILD_ROOT = build
DOCKER_BUILD_ROOT = docker-build
INSTALL_PREFIX = install
DOCKER_INSTALL_PREFIX = docker-install

OPENFOAM_BUILD = $(BUILD_ROOT)/openfoam-build
OPENFOAM_CLI_BUILD = $(BUILD_ROOT)/cli-build
# Product pack staging (etc/ + openfoam/ + embedded CLI); not a copy of openfoam-build/.
OPENFOAM_STAGE = $(BUILD_ROOT)/stage/pack
BUILD_PACK_DIR = $(BUILD_ROOT)/pack
BUILD_WHEEL_DIR = $(BUILD_ROOT)/wheel
DIST_NATIVE_DIR = $(BUILD_ROOT)/dist-native
DIST_DOCKER_DIR = $(BUILD_ROOT)/dist-docker
BUILD_DOCKER_DIR = $(BUILD_ROOT)/docker
BUILD_WHEEL_STAGE_DIR = $(BUILD_ROOT)/stage/cli-wheel
BUILD_WHEEL_TMP_DIR = $(BUILD_ROOT)/stage/wheel-build
BUILD_WHEEL_MATCH = openfoam_cli-*.whl
OPENFOAM_BUILD_MODULES = 0
OPENFOAM_SYSTEM_CHECK = auto
OPENFOAM_SKIP_ALLWMAKE = auto
OPENFOAM_BUNDLE_RUNTIME = 0

# --- Docker ---
DOCKER_UBUNTU_IMAGE_NAME = phynexis-ubuntu
DOCKER_BUILD_IMAGE_NAME = phynexis-build
DOCKER_OPENFOAM_IMAGE_NAME = openfoam
DOCKER_UBUNTU_VERSION = 24.04
DOCKER_REGISTRY =
# DOCKER_ARCH: leave unset so CI/env can set it without an empty override wiping it.
DOCKER_APT_MIRROR =
