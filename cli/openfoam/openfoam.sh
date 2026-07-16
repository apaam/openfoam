#!/usr/bin/env bash
# OpenFOAM CLI entry (native + docker).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
OpenFOAM CLI

Native:
  install <archive.tar.gz> [--prefix <dir>] [--force]
                                    Install a native pack (default prefix: /opt/openfoam)
  prefix [--path]                   Print OPENFOAM_PREFIX (resolved install root)
  completion bash|zsh               Tab completion
  run [-np <N>] <command> [args...] Run a command in the current directory
  shell [dir]                       Interactive shell (sources etc/bashrc)

Set OPENFOAM_PREFIX to your install root; source <prefix>/etc/bashrc

Docker:
  docker run [-np <N>] <command>... Same as native, in container (loads /root/.bashrc)
  docker shell [dir]                Interactive shell in container
  docker pull                       Download runtime image
  docker install-image [archive]    Load offline image (make dist-docker / docker-dist-docker)
  docker uninstall-image            Remove runtime image

Examples:
  pip install openfoam_cli-*.whl
  openfoam install openfoam-*.tar.gz
  export OPENFOAM_PREFIX=/opt/openfoam
  source "\$OPENFOAM_PREFIX/etc/bashrc"
  blockMesh -help
  openfoam run blockMesh
  openfoam run -np 4 icoFoam -parallel
  openfoam docker run ./Allrun

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
