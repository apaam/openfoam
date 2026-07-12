#!/usr/bin/env bash
# Build (or open a shell) inside phynexis-build with the repo bind-mounted.
#
# Usage:
#   bash docker/build_in_container.sh              # make dist-native
#   bash docker/build_in_container.sh shell         # interactive shell
#   bash docker/build_in_container.sh -- make all   # custom make target(s)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

MODE="build"
MAKE_ARGS=()
if [[ $# -gt 0 ]]; then
  case "$1" in
  shell)
    MODE="shell"
    shift
    ;;
  --)
    shift
    MAKE_ARGS=("$@")
    ;;
  *)
    MAKE_ARGS=("$@")
    ;;
  esac
fi
if [[ ${#MAKE_ARGS[@]} -eq 0 ]]; then
  MAKE_ARGS=(dist-native)
fi

PLATFORM="${DOCKER_PLATFORM:-}"
if [[ -z "${PLATFORM}" ]]; then
  case "$(uname -m)" in
  x86_64) PLATFORM=linux/amd64 ;;
  arm64|aarch64) PLATFORM=linux/arm64 ;;
  *) PLATFORM=linux/amd64 ;;
  esac
fi

UBUNTU_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
BUILD_IMAGE_NAME="${DOCKER_BUILD_IMAGE_NAME:-phynexis-build}"
TARGETARCH="${PLATFORM#linux/}"
IMAGE="${BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}"
APT_MIRROR="${DOCKER_APT_MIRROR:-}"
BUILD_JOBS="${BUILD_JOBS:-${NUM_JOBS:-4}}"
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[build_in_container] docker not found" >&2
  exit 1
fi

printf '==> Ensuring openfoam-source submodule\n'
git -c submodule.recurse=false submodule sync -- openfoam-source
git -c submodule.recurse=false submodule update --init --depth 1 -- openfoam-source

printf '==> Ensuring build image %s\n' "${IMAGE}"
DOCKER_PLATFORM="${PLATFORM}" \
  DOCKER_UBUNTU_VERSION="${UBUNTU_VERSION}" \
  DOCKER_BUILD_IMAGE_NAME="${BUILD_IMAGE_NAME}" \
  DOCKER_APT_MIRROR="${APT_MIRROR}" \
  bash "${ROOT}/docker/setup_build_image.sh"

run_container() {
  local -a docker_args=(
    run --rm
    --platform "${PLATFORM}"
    -v "${ROOT}:/src"
    -w /src
    -e "DEBIAN_FRONTEND=noninteractive"
    -e "BUILD_JOBS=${BUILD_JOBS}"
    -e "NUM_JOBS=${BUILD_JOBS}"
    -e "OPENFOAM_VERSION=${OPENFOAM_VERSION}"
  )
  if [[ "${MODE}" == "shell" ]]; then
    docker_args+=(-it)
  fi
  docker "${docker_args[@]}" "${IMAGE}" "$@"
}

if [[ "${MODE}" == "shell" ]]; then
  printf '==> Interactive shell in %s (%s)\n' "${IMAGE}" "${PLATFORM}"
  printf '    Inside: make dist-native   (or make all)\n'
  printf '    Exit:   exit\n'
  run_container bash -l
  exit 0
fi

printf '==> Container build: make'
printf ' %q' "${MAKE_ARGS[@]}"
printf '  [%s %s, jobs=%s]\n' "${IMAGE}" "${PLATFORM}" "${BUILD_JOBS}"
make_cmd='make'
for a in "${MAKE_ARGS[@]}"; do
  make_cmd+=" $(printf '%q' "${a}")"
done
run_container bash -lc "${make_cmd}"
printf '==> Done. Artifacts are under %s/build/\n' "${ROOT}"
printf '    Next (host): make dist-docker\n'
