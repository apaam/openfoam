#!/usr/bin/env bash
# Docker runtime launcher (phynexis-foam docker).
#
# Install: pip install phynexis_foam-*.whl  (make wheel)
# Native:  tar xzf phynexis-foam-*.tar.gz -C <prefix>  (make dist-native)
#   phynexis-foam docker install-image [image.tar.gz]
#   phynexis-foam docker pull
#
# Usage:
#   phynexis-foam docker run blockMesh
#   phynexis-foam docker run -np 4 icoFoam -parallel
#   phynexis-foam docker shell .

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=shell_prompt.sh
source "${SCRIPT_DIR}/shell_prompt.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${REPO_ROOT}/scripts/openfoam_build_paths.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/openfoam_build_paths.sh"
  openfoam_load_build_paths "${REPO_ROOT}"
elif [[ -f "${REPO_ROOT}/scripts/load_make_config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/load_make_config.sh"
  load_make_config "${REPO_ROOT}"
fi

default_openfoam_image() {
  local registry="${DOCKER_REGISTRY:-}"
  local name="${DOCKER_OPENFOAM_IMAGE_NAME:-phynexis-foam}"
  local version="${OPENFOAM_VERSION:-v2412}"
  version="${version#v}"
  local arch="${DOCKER_ARCH:-}"
  if [[ -z "${arch}" ]]; then
    case "$(uname -m)" in
    arm64 | aarch64) arch="arm64" ;;
    *) arch="amd64" ;;
    esac
  fi
  registry="${registry%/}"
  if [[ -n "${registry}" ]]; then
    printf '%s' "${registry}/${name}:${version}-${arch}"
  else
    printf '%s' "${name}:${version}-${arch}"
  fi
}

OPENFOAM_IMAGE="${OPENFOAM_IMAGE:-$(default_openfoam_image)}"
CLI_PREFIX="${OPENFOAM_CLI_PREFIX:-phynexis-foam docker}"

platform_args() {
  case "${OPENFOAM_IMAGE}" in
  *-amd64) printf '%s' '--platform linux/amd64' ;;
  *-arm64) printf '%s' '--platform linux/arm64' ;;
  *) ;;
  esac
}

require_docker() {
  if ! command -v docker >/dev/null; then
    echo "Docker not found. Install Docker Desktop or Docker Engine first." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but not running. Start Docker Desktop (or the daemon) and retry." >&2
    exit 1
  fi
}

abs_path() {
  local path="$1"
  if command -v realpath >/dev/null; then
    realpath "${path}"
  else
    python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${path}"
  fi
}

find_pack_archive() {
  local name dir
  for name in "$(docker_dist_basename).tar.gz" "$(pack_basename).tar.gz"; do
    for dir in "${SCRIPT_DIR}" \
      "${REPO_ROOT}/${DIST_DOCKER_DIR:-${BUILD_ROOT:-build}/dist-docker}" \
      "${REPO_ROOT}/${BUILD_DOCKER_DIR:-${BUILD_ROOT:-build}/docker}" \
      "${REPO_ROOT}/${DOCKER_BUILD_ROOT:-docker-build}/dist-docker" \
      "${REPO_ROOT}/${DOCKER_BUILD_ROOT:-docker-build}/docker" \
      "$(pwd)"; do
      if [[ -f "${dir}/${name}" ]]; then
        abs_path "${dir}/${name}"
        return 0
      fi
    done
  done
  for name in "$(docker_dist_basename).tar" "$(pack_basename).tar"; do
    for dir in "${SCRIPT_DIR}" \
      "${REPO_ROOT}/${DIST_DOCKER_DIR:-${BUILD_ROOT:-build}/dist-docker}" \
      "${REPO_ROOT}/${BUILD_DOCKER_DIR:-${BUILD_ROOT:-build}/docker}" \
      "${REPO_ROOT}/${DOCKER_BUILD_ROOT:-docker-build}/dist-docker" \
      "${REPO_ROOT}/${DOCKER_BUILD_ROOT:-docker-build}/docker" \
      "$(pwd)"; do
      if [[ -f "${dir}/${name}" ]]; then
        abs_path "${dir}/${name}"
        return 0
      fi
    done
  done
  return 1
}

docker_dist_basename() {
  local version="${OPENFOAM_VERSION:-v2412}"
  version="${version#v}"
  local arch="${DOCKER_ARCH:-}"
  if [[ -z "${arch}" ]]; then
    case "$(uname -m)" in
    arm64 | aarch64) arch="arm64" ;;
    *) arch="amd64" ;;
    esac
  fi
  printf 'phynexis-foam-docker-%s-linux-%s' "${version}" "${arch}"
}

pack_basename() {
  printf '%s' "${OPENFOAM_IMAGE}" | tr '/:' '-'
}

# Non-interactive bash does not load ~/.bashrc; source it for parity with docker shell.
docker_run_bashrc() {
  local work_dir="$1"
  shift
  local inner
  inner="$(printf 'source "${HOME}/.bashrc" && '; printf '%q ' "$@")"
  docker_run_raw "${work_dir}" bash -c "${inner}"
}

docker_common_args() {
  printf '%s' \
    '-e OMPI_ALLOW_RUN_AS_ROOT=1 -e OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1'
}

usage() {
  cat <<EOF
${CLI_PREFIX} — run OpenFOAM in Docker

Image admin:
  install-image [image.tar.gz]      Load offline image archive (make dist-docker / docker-dist-docker)
  uninstall-image                   Remove the runtime Docker image
  pull                              Download the runtime image from a registry

Run:
  run [-np <N>] <command> [args...] Run a command in the current directory (container)
  shell [dir]                       Interactive shell (default: current directory)

Environment:
  OPENFOAM_IMAGE   Docker image (default: ${OPENFOAM_IMAGE})
  OPENFOAM_PACK    Offline archive path (optional, for install-image)

Examples:
  ${CLI_PREFIX} pull
  ${CLI_PREFIX} run blockMesh
  ${CLI_PREFIX} run -np 4 icoFoam -parallel
  ${CLI_PREFIX} run ./Allrun
  ${CLI_PREFIX} shell .

Case inputs and outputs stay on your machine.
EOF
}

cmd_install_image() {
  require_docker
  local archive="${1:-${OPENFOAM_PACK:-}}"
  if [[ -z "${archive}" ]]; then
    if ! archive="$(find_pack_archive)"; then
      echo "Offline image archive not found." >&2
      echo "Run: ${CLI_PREFIX} install-image <path/to/$(docker_dist_basename).tar.gz>" >&2
      exit 1
    fi
  fi
  archive="$(abs_path "${archive}")"
  if [[ ! -f "${archive}" ]]; then
    echo "Archive not found: ${archive}" >&2
    exit 1
  fi
  case "${archive}" in
  *.tar.gz | *.tgz)
    gunzip -c "${archive}" | docker load
    ;;
  *.tar)
    docker load -i "${archive}"
    ;;
  *)
    echo "Unsupported archive format (expected .tar.gz or .tar): ${archive}" >&2
    exit 1
    ;;
  esac
  if ! docker image inspect "${OPENFOAM_IMAGE}" >/dev/null 2>&1; then
    echo "Archive loaded, but image ${OPENFOAM_IMAGE} is not available." >&2
    echo "Set OPENFOAM_IMAGE to the tag shown by 'docker load' above." >&2
    exit 1
  fi
  echo "Installed ${OPENFOAM_IMAGE}"
}

cmd_uninstall_image() {
  require_docker
  if ! docker image inspect "${OPENFOAM_IMAGE}" >/dev/null 2>&1; then
    echo "Image not found: ${OPENFOAM_IMAGE}" >&2
    exit 1
  fi
  docker rmi "${OPENFOAM_IMAGE}"
  echo "Removed ${OPENFOAM_IMAGE}"
}

cmd_pull() {
  require_docker
  local platform
  platform="$(platform_args)"
  if [[ -n "${platform}" ]]; then
    # shellcheck disable=SC2086
    docker pull ${platform} "${OPENFOAM_IMAGE}"
  else
    docker pull "${OPENFOAM_IMAGE}"
  fi
}

docker_run_raw() {
  require_docker
  local platform work_dir common
  platform="$(platform_args)"
  common="$(docker_common_args)"
  work_dir="$(abs_path "$1")"
  shift
  if [[ ! -d "${work_dir}" ]]; then
    echo "Directory not found: ${work_dir}" >&2
    exit 1
  fi
  if [[ -n "${platform}" ]]; then
    # shellcheck disable=SC2086
    docker run ${platform} --rm ${common} -v "${work_dir}:/work" -w /work \
      "${OPENFOAM_IMAGE}" "$@"
  else
    # shellcheck disable=SC2086
    docker run --rm ${common} -v "${work_dir}:/work" -w /work \
      "${OPENFOAM_IMAGE}" "$@"
  fi
}

cmd_shell() {
  local work_dir="${1:-.}"
  require_docker
  local platform inner common pkg_src pkg_host pkg_container wrapper_container
  platform="$(platform_args)"
  common="$(docker_common_args)"
  work_dir="$(abs_path "${work_dir}")"
  if [[ ! -d "${work_dir}" ]]; then
    echo "Directory not found: ${work_dir}" >&2
    exit 1
  fi
  # Copy CLI shell files to /tmp so Docker Desktop can mount them (site-packages
  # under /opt/homebrew is not shared by default on macOS).
  pkg_src="$(openfoam_shell_bashrc_path)"
  pkg_host="$(mktemp -d "/tmp/phynexis-foam-docker-shell.XXXXXX")"
  # Expand path now: EXIT trap runs after locals are gone (set -u would fail).
  trap "rm -rf $(printf '%q' "${pkg_host}")" EXIT
  cp "${pkg_src}/shell_bashrc.sh" "${pkg_host}/"
  if [[ -f "${pkg_src}/completion.bash" ]]; then
    cp "${pkg_src}/completion.bash" "${pkg_host}/"
  fi
  pkg_container="/etc/phynexis-foam"
  wrapper_container="${pkg_container}/shell_bashrc.sh"
  # Env comes from /root/.bashrc via shell_bashrc.sh (same as phynexis-v0).
  inner="$(openfoam_interactive_shell_cmd "phynexis-foam:docker" \
    "${wrapper_container}" "${pkg_container}")"
  # Do not exec: keep trap so pkg_host is removed after the container exits.
  if [[ -n "${platform}" ]]; then
    # shellcheck disable=SC2086
    docker run ${platform} --rm -it ${common} \
      -v "${work_dir}:/work" -w /work \
      -v "${pkg_host}:${pkg_container}:ro" \
      "${OPENFOAM_IMAGE}" bash -lc "${inner}"
  else
    # shellcheck disable=SC2086
    docker run --rm -it ${common} \
      -v "${work_dir}:/work" -w /work \
      -v "${pkg_host}:${pkg_container}:ro" \
      "${OPENFOAM_IMAGE}" bash -lc "${inner}"
  fi
}

resolve_run_target() {
  RUN_WORK_DIR="$(pwd)"
  RUN_CMD=()
  local np=""

  if (("$#" == 0)); then
    echo "Usage: ${CLI_PREFIX} run [-np <N>] <command> [args...]" >&2
    exit 1
  fi

  while (("$#" > 0)); do
    case "$1" in
    -np | --np)
      if (("$#" < 2)); then
        echo "Missing value for $1" >&2
        exit 1
      fi
      np="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      break
      ;;
    *)
      break
      ;;
    esac
  done

  if (("$#" == 0)); then
    echo "Usage: ${CLI_PREFIX} run [-np <N>] <command> [args...]" >&2
    exit 1
  fi

  if [[ -n "${np}" ]]; then
    if [[ ! "${np}" =~ ^[1-9][0-9]*$ ]]; then
      echo "Invalid -np value: ${np}" >&2
      exit 1
    fi
    RUN_CMD=(mpirun -np "${np}" "$@")
  else
    RUN_CMD=("$@")
  fi
}

cmd_run() {
  resolve_run_target "$@"
  docker_run_bashrc "${RUN_WORK_DIR}" "${RUN_CMD[@]}"
}

unknown_cmd() {
  local cmd="$1"
  echo "Unknown command: ${cmd}" >&2
  echo "Run: ${CLI_PREFIX} help" >&2
  exit 1
}

main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
  install-image) cmd_install_image "$@" ;;
  uninstall-image) cmd_uninstall_image "$@" ;;
  pull) cmd_pull "$@" ;;
  run) cmd_run "$@" ;;
  shell) cmd_shell "$@" ;;
  -h | --help | help | "") usage ;;
  *) unknown_cmd "${cmd}" ;;
  esac
}

main "$@"
