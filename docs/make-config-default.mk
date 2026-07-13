# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).
#
# Path model:
#   BUILD_ROOT       — active build tree (compile / pack / make clean)
#   DOCKER_BUILD_ROOT — used when CONTAINER_BUILD=1 (docker-shell)
#   OPENFOAM_PREFIX  — runtime install root (CLI; default /opt/openfoam; not set here)
#
# Prefer changing BUILD_ROOT / DOCKER_BUILD_ROOT; keep derived paths as $(BUILD_ROOT)/...
# so docker-shell remapping stays consistent. make clean only removes $(BUILD_ROOT).

# --- Native build (make openfoam / cli / all) ---
BUILD_JOBS = 4
BUILD_PY = python3
OPENFOAM_VERSION = v2412

BUILD_ROOT = build
DOCKER_BUILD_ROOT = docker-build

OPENFOAM_BUILD = $(BUILD_ROOT)/openfoam-build
OPENFOAM_CLI_BUILD = $(BUILD_ROOT)
OPENFOAM_STAGE = $(BUILD_ROOT)/stage/openfoam-build
BUILD_OPENFOAM_PACK_DIR = $(BUILD_ROOT)/openfoam-pack
DIST_NATIVE_DIR = $(BUILD_ROOT)/dist-native
DIST_DOCKER_DIR = $(BUILD_ROOT)/dist-docker
BUILD_DOCKER_DIR = $(BUILD_ROOT)/docker
BUILD_CLI_PACK_DIR = $(BUILD_ROOT)/cli-pack
BUILD_CLI_WHEEL_DIR = $(BUILD_ROOT)/cli-wheel
BUILD_CLI_BUILD_DIR = $(BUILD_ROOT)/cli-build
BUILD_CLI_WHEEL_STAGE_DIR = $(BUILD_ROOT)/stage/cli-wheel
BUILD_CLI_WHEEL_MATCH = openfoam_cli-*.whl
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
DOCKER_ARCH =
DOCKER_APT_MIRROR =
