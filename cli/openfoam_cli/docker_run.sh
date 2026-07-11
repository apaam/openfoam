#!/usr/bin/env bash
# Docker runtime launcher (openfoam docker).
#
# Install: pip install openfoam-*.whl  (make cli / make docker-dist)
# Native:  pip install openfoam-*.whl  (make wheel-dist) or cpack extract
#   openfoam docker install-image [image.tar.gz]
#   openfoam docker pull
#
# Usage:
#   openfoam docker run ~/my_case/Allrun
#   openfoam docker blockMesh -help
#   openfoam docker shell .

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [[ -f "${REPO_ROOT}/scripts/load_make_config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/load_make_config.sh"
  load_make_config "${REPO_ROOT}"
fi

default_openfoam_image() {
  local registry="${DOCKER_REGISTRY:-}"
  local name="${DOCKER_OPENFOAM_IMAGE_NAME:-openfoam}"
  local version="${DOCKER_UBUNTU_VERSION:-24.04}"
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
OPENFOAM_BASHRC="${OPENFOAM_BASHRC:-/opt/openfoam/etc/bashrc}"
CLI_PREFIX="${OPENFOAM_CLI_PREFIX:-openfoam docker}"

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
    echo "Docker is installed but not running. Start Docker and retry." >&2
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
  name="$(pack_basename).tar.gz"
  for dir in "${SCRIPT_DIR}" "${REPO_ROOT}/${DOCKER_DIST_DIR:-build/docker-dist}" "$(pwd)"; do
    if [[ -f "${dir}/${name}" ]]; then
      abs_path "${dir}/${name}"
      return 0
    fi
  done
  name="$(pack_basename).tar"
  for dir in "${SCRIPT_DIR}" "${REPO_ROOT}/${DOCKER_DIST_DIR:-build/docker-dist}" "$(pwd)"; do
    if [[ -f "${dir}/${name}" ]]; then
      abs_path "${dir}/${name}"
      return 0
    fi
  done
  return 1
}

pack_basename() {
  printf '%s' "${OPENFOAM_IMAGE}" | tr '/:' '-'
}

openfoam_shell_cmd() {
  local inner="$1"
  printf 'source %q && %s' "${OPENFOAM_BASHRC}" "${inner}"
}

docker_common_args() {
  printf '%s' \
    '-e OMPI_ALLOW_RUN_AS_ROOT=1 -e OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1'
}

usage() {
  cat <<EOF
${CLI_PREFIX} — run OpenFOAM in Docker

Image admin:
  install-image [image.tar.gz]      Load offline image archive (from make docker-dist)
  uninstall-image                   Remove the runtime Docker image
  pull                              Download the runtime image from a registry

Run:
  run <script|command> [args...]    Run a script in its directory, or a command in cwd
  shell [dir]                       Interactive shell (default: current directory)
  blockMesh -help                   Run any OpenFOAM command (shorthand)

Environment:
  OPENFOAM_IMAGE   Docker image (default: ${OPENFOAM_IMAGE})
  OPENFOAM_PACK    Offline archive path (optional, for install-image)

Examples:
  openfoam docker pull
  openfoam docker run ~/case/Allrun
  openfoam docker blockMesh -help
  openfoam docker shell .

Case inputs and outputs stay on your machine.
EOF
}

cmd_install_image() {
  require_docker
  local archive="${1:-${OPENFOAM_PACK:-}}"
  if [[ -z "${archive}" ]]; then
    if ! archive="$(find_pack_archive)"; then
      echo "Offline image archive not found." >&2
      echo "Run: openfoam docker install-image <path/to/$(pack_basename).tar.gz>" >&2
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

docker_run_openfoam() {
  local work_dir inner
  work_dir="$1"
  shift
  inner="$(openfoam_shell_cmd "$(printf '%q ' "$@")")"
  docker_run_raw "${work_dir}" bash -lc "${inner}"
}

cmd_shell() {
  local work_dir="${1:-.}"
  require_docker
  local platform inner common
  platform="$(platform_args)"
  common="$(docker_common_args)"
  work_dir="$(abs_path "${work_dir}")"
  if [[ ! -d "${work_dir}" ]]; then
    echo "Directory not found: ${work_dir}" >&2
    exit 1
  fi
  inner="$(openfoam_shell_cmd 'exec bash')"
  if [[ -n "${platform}" ]]; then
    # shellcheck disable=SC2086
    exec docker run ${platform} --rm -it ${common} -v "${work_dir}:/work" -w /work \
      "${OPENFOAM_IMAGE}" bash -lc "${inner}"
  else
    # shellcheck disable=SC2086
    exec docker run --rm -it ${common} -v "${work_dir}:/work" -w /work \
      "${OPENFOAM_IMAGE}" bash -lc "${inner}"
  fi
}

resolve_run_target() {
  RUN_WORK_DIR=""
  RUN_CMD=()

  if (("$#" == 0)); then
    echo "Usage: ${CLI_PREFIX} run <script|command> [args...]" >&2
    exit 1
  fi

  local first="$1"
  if [[ -f "${first}" ]]; then
    first="$(abs_path "${first}")"
    RUN_WORK_DIR="$(dirname "${first}")"
    RUN_CMD=("./$(basename "${first}")")
    shift
    if (("$#" > 0)); then
      RUN_CMD+=("$@")
    fi
  elif [[ -d "${first}" ]]; then
    echo "Pass a script file, e.g. ${CLI_PREFIX} run ${first}/Allrun" >&2
    echo "Or: ${CLI_PREFIX} shell ${first}" >&2
    exit 1
  else
    RUN_WORK_DIR="$(pwd)"
    RUN_CMD=("$@")
  fi
}

cmd_run() {
  resolve_run_target "$@"
  docker_run_openfoam "${RUN_WORK_DIR}" "${RUN_CMD[@]}"
}

cmd_exec() {
  if (("$#" == 0)); then
    echo "Usage: ${CLI_PREFIX} run ~/case/Allrun" >&2
    echo "       ${CLI_PREFIX} blockMesh -help" >&2
    exit 1
  fi

  local first="$1"
  if [[ -f "${first}" ]]; then
    echo "Use: ${CLI_PREFIX} run ${first}" >&2
    exit 1
  fi
  if [[ -d "${first}" ]]; then
    echo "Use: ${CLI_PREFIX} run ${first}/Allrun" >&2
    echo "Or: ${CLI_PREFIX} shell ${first}" >&2
    exit 1
  fi

  docker_run_openfoam "$(pwd)" "$@"
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
  *) cmd_exec "${cmd}" "$@" ;;
  esac
}

main "$@"
