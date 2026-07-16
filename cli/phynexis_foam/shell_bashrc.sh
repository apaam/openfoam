#!/usr/bin/env bash
# Bash --rcfile wrapper for phynexis-foam shell: load user bashrc, then add prompt prefix.

if [[ -f "${HOME}/.bashrc" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/.bashrc"
fi

if [[ -n "${OPENFOAM_SHELL:-}" && -z "${OPENFOAM_PS1_APPLIED:-}" ]]; then
  export OPENFOAM_PS1_APPLIED=1
  PS1="(${OPENFOAM_SHELL_TAG:-phynexis-foam}) ${PS1:-$ }"
fi

# Functions from etc/bashrc are lost across exec bash; reload completions here.
if [[ -n "${WM_PROJECT_DIR:-}" && -f "${WM_PROJECT_DIR}/etc/config.sh/bash_completion" ]]; then
  # shellcheck disable=SC1090
  source "${WM_PROJECT_DIR}/etc/config.sh/bash_completion"
fi

if [[ -n "${OPENFOAM_PACKAGE_DIR:-}" && -f "${OPENFOAM_PACKAGE_DIR}/completion.bash" ]]; then
  # shellcheck disable=SC1090
  source "${OPENFOAM_PACKAGE_DIR}/completion.bash"
fi
