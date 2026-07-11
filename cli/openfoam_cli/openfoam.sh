#!/usr/bin/env bash
# OpenFOAM CLI entry (native + docker).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
OpenFOAM CLI

Native (wheel / cpack / local build):
  env                               Print shell snippet to source etc/bashrc
  completion bash|zsh               Print tab-completion script
  run <script|command> [args...]    Run a script in its directory, or a command in cwd
  shell [dir]                       Interactive shell
  blockMesh -help                   Run any OpenFOAM command (shorthand)

Docker:
  docker run <script|command> ...   Same as native, in container
  docker shell [dir]                Interactive shell in container
  docker pull                       Download runtime image
  docker install-image [archive]    Load offline image (make docker-dist)
  docker uninstall-image            Remove runtime image

Examples:
  eval "\$(openfoam env)" && wmake
  eval "\$(openfoam completion bash)"   # or: completion zsh
  openfoam run ~/my_case/Allrun
  openfoam blockMesh -help
  openfoam docker pull
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
