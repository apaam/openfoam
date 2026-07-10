# Default Makefile configuration (tracked).
# Override in make-config-user.mk at the project root (git-ignored).

# --- Native build (make / install / v2412) ---
BUILD_JOBS = 4
OPENFOAM_VERSION = v2412

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

# --- Docker paths ---
DOCKER_DIST_DIR = build/docker-dist

# Optional apt mirror passed to docker/apt_setup.sh
DOCKER_APT_MIRROR =
