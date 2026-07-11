# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).

# --- Native build (make / install / wheel / cpack) ---
BUILD_JOBS = 4
BUILD_PY = python3
OPENFOAM_VERSION = v2412
OPENFOAM_BUILD = build
OPENFOAM_STAGE = build/stage/openfoam
BUILD_WHEEL_DIR = build/wheel
BUILD_WHEEL_DIST_DIR = build/wheel-dist
BUILD_CPACK_DIR = build/cpack
BUILD_CPACK_DIST_DIR = build/cpack-dist
BUILD_WHEEL_MATCH = openfoam-*.whl
# 0 = core OpenFOAM only (src + applications); 1 = also build modules
OPENFOAM_BUILD_MODULES = 0
# foamSystemCheck: auto = skip when build/platforms exists; 1 = always; 0 = never
OPENFOAM_SYSTEM_CHECK = auto
# Allwmake: auto = skip when source/config unchanged and build/ is current; 0 = always run
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

# Docker release bundle: image tar.gz + openfoam-*.whl
DOCKER_DIST_DIR = build/docker-dist

# Optional apt mirror passed to docker/apt_setup.sh
DOCKER_APT_MIRROR =
