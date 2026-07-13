#!/usr/bin/env bash

openfoam_shell_bashrc_path() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

openfoam_interactive_shell_cmd() {
  local tag="$1"
  local bashrc="$2"
  local wrapper="${3:-$(openfoam_shell_bashrc_path)/shell_bashrc.sh}"
  local cli_dir="${4:-$(openfoam_shell_bashrc_path)}"
  printf 'source %q && export OPENFOAM_SHELL=1 OPENFOAM_SHELL_TAG=%q OPENFOAM_PACKAGE_DIR=%q && exec bash --rcfile %q -i' \
    "${bashrc}" "${tag}" "${cli_dir}" "${wrapper}"
}
