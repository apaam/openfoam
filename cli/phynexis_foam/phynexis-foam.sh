#!/usr/bin/env bash
# phynexis-foam CLI entry (native + docker).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
phynexis-foam — OpenFOAM CLI

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
  pip install phynexis_foam-*.whl
  phynexis-foam install phynexis-foam-*.tar.gz
  export OPENFOAM_PREFIX=/opt/openfoam
  source "\$OPENFOAM_PREFIX/etc/bashrc"
  blockMesh -help
  phynexis-foam run blockMesh
  phynexis-foam run -np 4 icoFoam -parallel
  phynexis-foam docker run ./Allrun

See also: phynexis-foam docker help
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
