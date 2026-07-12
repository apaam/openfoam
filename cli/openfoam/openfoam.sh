#!/usr/bin/env bash
# OpenFOAM CLI entry (native + docker).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
OpenFOAM CLI

Native (wheel / cpack / local build):
  prefix                            Print install root (default /opt/openfoam)
  dev install|clean                 Install/remove OpenFOAM under OPENFOAM_PREFIX
  completion bash|zsh               Tab completion
  run <script> [args...]            Run a script in its directory
  shell [dir]                       Interactive shell (sources etc/bashrc)

Set OPENFOAM_PREFIX to your install root; source <prefix>/etc/bashrc

Docker:
  docker run <script> ...           Same as native, in container
  docker shell [dir]                Interactive shell in container
  docker pull                       Download runtime image
  docker install-image [archive]    Load offline image (make docker-dist)
  docker uninstall-image            Remove runtime image

Examples:
  pip install openfoam-*.whl
  export OPENFOAM_PREFIX=/Volumes/OpenFOAM/opt/openfoam
  openfoam dev install
  source "\$OPENFOAM_PREFIX/etc/bashrc"
  blockMesh -help
  openfoam run ~/my_case/Allrun
  openfoam docker run ~/my_case/Allrun

See also: openfoam docker help
EOF
}

main() {
  local cmd="${1:-}"

  if [[ -z "${cmd}" || "${cmd}" == "-h" || "${cmd}" == "help" || "${cmd}" == "--help" ]]; then
    usage
    return 0
  fi

  case "${cmd}" in
  docker)
    shift
    exec bash "${SCRIPT_DIR}/docker_run.sh" "$@"
    ;;
  *)
    # shellcheck source=native.sh
    source "${SCRIPT_DIR}/native.sh"
    native_main "$@"
    ;;
  esac
}

main "$@"
