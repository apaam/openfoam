# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).

# --- Native build (make openfoam / cli / all) ---
BUILD_JOBS = 4
BUILD_PY = python3
OPENFOAM_VERSION = v2412
OPENFOAM_BUILD = build/openfoam-build
OPENFOAM_CLI_BUILD = build
OPENFOAM_STAGE = build/stage/openfoam-build
BUILD_OPENFOAM_PACK_DIR = build/openfoam-pack
DIST_NATIVE_DIR = build/dist-native
BUILD_CLI_PACK_DIR = build/cli-pack
BUILD_CLI_WHEEL_DIR = build/cli-wheel
BUILD_CLI_BUILD_DIR = build/cli-build
BUILD_CLI_WHEEL_MATCH = openfoam_cli-*.whl
OPENFOAM_BUILD_MODULES = 0
OPENFOAM_SYSTEM_CHECK = auto
OPENFOAM_SKIP_ALLWMAKE = auto
OPENFOAM_BUNDLE_RUNTIME = 0

# --- Docker image (from linux dist-native) ---
DOCKER_UBUNTU_IMAGE_NAME = phynexis-ubuntu
DOCKER_OPENFOAM_IMAGE_NAME = openfoam
DOCKER_UBUNTU_VERSION = 24.04
DOCKER_REGISTRY =
DOCKER_ARCH =

BUILD_DOCKER_DIR = build/docker
DIST_DOCKER_DIR = build/dist-docker
DOCKER_APT_MIRROR =
