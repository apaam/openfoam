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
BUILD_CLI_WHEEL_STAGE_DIR = build/stage/cli-wheel
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

# Host packaging intermediates / release
BUILD_DOCKER_DIR = build/docker
DIST_DOCKER_DIR = build/dist-docker

# docker-shell (CONTAINER_BUILD=1): isolated tree mirroring host build/
BUILD_DOCKER_ROOT = build/docker
DOCKER_OPENFOAM_BUILD = build/docker/openfoam-build
DOCKER_OPENFOAM_CLI_BUILD = build/docker
DOCKER_OPENFOAM_STAGE = build/docker/stage/openfoam-build
DOCKER_BUILD_OPENFOAM_PACK_DIR = build/docker/openfoam-pack
DOCKER_DIST_NATIVE_DIR = build/docker/dist-native
DOCKER_DIST_DOCKER_DIR = build/docker/dist-docker
DOCKER_BUILD_CLI_PACK_DIR = build/docker/cli-pack
DOCKER_BUILD_CLI_WHEEL_DIR = build/docker/cli-wheel
DOCKER_BUILD_CLI_BUILD_DIR = build/docker/cli-build
DOCKER_BUILD_CLI_WHEEL_STAGE_DIR = build/docker/stage/cli-wheel
DOCKER_BUILD_DOCKER_DIR = build/docker
