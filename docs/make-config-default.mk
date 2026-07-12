# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).

# --- Native build (make / install / wheel / cpack) ---
BUILD_JOBS = 4
BUILD_PY = python3
OPENFOAM_VERSION = v2412
# WM_PROJECT_DIR on host (native compile); docker uses DOCKER_OPENFOAM_BUILD.
OPENFOAM_BUILD = build/host-build
# Local CLI install root (separate from OPENFOAM_BUILD); override in make-config-user.mk
OPENFOAM_CLI_BUILD = build/cli
OPENFOAM_STAGE = build/stage/host-build
BUILD_WHEEL_DIR = build/wheel
BUILD_WHEEL_DIST_DIR = build/wheel-dist
BUILD_CPACK_DIR = build/cpack
BUILD_CPACK_DIST_DIR = build/cpack-dist
BUILD_WHEEL_MATCH = openfoam-*.whl
# 0 = core OpenFOAM only (src + applications); 1 = also build modules
OPENFOAM_BUILD_MODULES = 0
# foamSystemCheck: auto = skip when OPENFOAM_BUILD/platforms exists; 1 = always; 0 = never
OPENFOAM_SYSTEM_CHECK = auto
# Allwmake: auto = skip when source/config unchanged and $(OPENFOAM_BUILD) is current; 0 = always run
OPENFOAM_SKIP_ALLWMAKE = auto
# Bundle dylibs for distributable wheel/cpack (-dist targets); 0 for local wheel/cpack
OPENFOAM_BUNDLE_RUNTIME = 0

# --- Docker image naming ---
DOCKER_UBUNTU_IMAGE_NAME = phynexis-ubuntu
DOCKER_BUILD_IMAGE_NAME = phynexis-build
DOCKER_OPENFOAM_IMAGE_NAME = openfoam
DOCKER_UBUNTU_VERSION = 24.04

# Registry prefix for docker-push, e.g. ghcr.io/myorg
# Leave empty for local-only tags (openfoam:24.04-amd64).
DOCKER_REGISTRY =

# Target arch: amd64 | arm64 | leave empty for host auto-detect
DOCKER_ARCH =

# --- Docker build ---
DOCKER_JOBS = 4
# Bump when docker/phynexis_build_packages.txt changes (triggers extend on next build).
PHYNEXIS_BUILD_DEPS_REV = 1
# Bump when docker/resolve_runtime_apt.sh changes (rebuilds runtime layer).
OPENFOAM_RUNTIME_DEPS_REV = 1

# Docker compile tree (Linux WM_PROJECT_DIR; isolated from OPENFOAM_BUILD / host-build)
DOCKER_OPENFOAM_BUILD = build/docker-build
DOCKER_OPENFOAM_STAGE = build/stage/docker-build

# Docker build workspace (image tar.gz + CLI wheel from docker-build / cli)
BUILD_DOCKER_DIR = build/docker
# Docker release bundle: copy of BUILD_DOCKER_DIR artifacts for distribution
DOCKER_DIST_DIR = build/docker-dist

# Optional apt mirror passed to docker/apt_setup.sh
DOCKER_APT_MIRROR =
