#!/usr/bin/env bash

openfoam_shell_bashrc_path() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Packaged installs wire bundled MPI via etc/config.sh/prefs.sys-openmpi;
# sourcing etc/bashrc is enough (no extra PATH/LD snippet).
openfoam_source_bashrc_cmd() {
  local bashrc="$1"
  local inner="$2"
  printf 'source %q && %s' "${bashrc}" "${inner}"
}

# Interactive shell: rely on --rcfile (shell_bashrc.sh → ~/.bashrc in Docker).
# Native callers should wrap with openfoam_source_bashrc_cmd / openfoam_shell_cmd.
openfoam_interactive_shell_cmd() {
  local tag="$1"
  local wrapper="${2:-$(openfoam_shell_bashrc_path)/shell_bashrc.sh}"
  local cli_dir="${3:-$(openfoam_shell_bashrc_path)}"
  printf 'export OPENFOAM_SHELL=1 OPENFOAM_SHELL_TAG=%q OPENFOAM_PACKAGE_DIR=%q && exec bash --rcfile %q -i' \
    "${tag}" "${cli_dir}" "${wrapper}"
}
