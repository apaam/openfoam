#!/usr/bin/env bash
# Native OpenFOAM launcher (openfoam env / run / shell / <command>).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prefix.sh
source "${SCRIPT_DIR}/prefix.sh"
# shellcheck source=shell_prompt.sh
source "${SCRIPT_DIR}/shell_prompt.sh"

CLI_PREFIX="${OPENFOAM_CLI_PREFIX:-openfoam}"

abs_path() {
  local path="$1"
  if command -v realpath >/dev/null; then
    realpath "${path}"
  else
    "${OPENFOAM_PYTHON:-python3}" -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${path}"
  fi
}

openfoam_shell_cmd() {
  local inner="$1"
  printf 'source %q && %s' "${OPENFOAM_BASHRC}" "${inner}"
}

usage() {
  cat <<EOF
${CLI_PREFIX} — native OpenFOAM commands

Developer:
  env                               Print 'source .../etc/bashrc' (native; use: eval "\$(openfoam env)")
  env-path                          Print PATH export for openfoam CLI
  completion bash|zsh               Tab completion

Run:
  run <script|command> [args...]    Run a script in its directory, or a command in cwd
  shell [dir]                       Interactive shell (sources etc/bashrc)
  blockMesh -help                   Run any OpenFOAM command (shorthand)

Examples:
  source build/openfoam/etc/bashrc  # native (local build; path known)
  eval "\$(openfoam env)" && wmake  # wheel, or when prefix path is unknown
  openfoam run ~/case/Allrun
  openfoam blockMesh -help
  openfoam shell .
EOF
}

cmd_env() {
  require_native_prefix
  printf 'source %s' "${OPENFOAM_BASHRC}"
}

cmd_env_path() {
  require_native_prefix
  local cli_bin="" cli_root=""

  if cli_bin="$(command -v openfoam 2>/dev/null)"; then
    printf 'export PATH=%q:${PATH}\n' "$(dirname "${cli_bin}")"
    return 0
  fi
  if [[ "${SCRIPT_DIR}" == */share/openfoam/cli ]]; then
    cli_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
    if [[ -x "${cli_root}/bin/openfoam" ]]; then
      printf 'export PATH=%q:${PATH}\n' "${cli_root}/bin"
      return 0
    fi
  fi
  if [[ -x "${OPENFOAM_PREFIX}/bin/openfoam" ]]; then
    printf 'export PATH=%q:${PATH}\n' "${OPENFOAM_PREFIX}/bin"
    return 0
  fi
  echo "openfoam not in PATH; add <cli>/bin or <prefix>/bin" >&2
  exit 1
}

cmd_completion() {
  local shell="${1:-}"
  if [[ -z "${shell}" ]]; then
    echo "Usage: ${CLI_PREFIX} completion bash|zsh" >&2
    exit 1
  fi
  case "${shell}" in
  bash)
    printf 'OPENFOAM_PACKAGE_DIR=%q\n' "${SCRIPT_DIR}"
    cat "${SCRIPT_DIR}/completion.bash"
    ;;
  zsh)
    printf 'typeset -g OPENFOAM_PACKAGE_DIR=%q\n' "${SCRIPT_DIR}"
    cat "${SCRIPT_DIR}/completion.zsh"
    ;;
  *)
    echo "Unsupported shell: ${shell} (supported: bash, zsh)" >&2
    exit 1
    ;;
  esac
}

native_run() {
  require_native_prefix
  local work_dir="$1"
  shift
  work_dir="$(abs_path "${work_dir}")"
  if [[ ! -d "${work_dir}" ]]; then
    echo "Directory not found: ${work_dir}" >&2
    exit 1
  fi
  local inner
  inner="$(openfoam_shell_cmd "$(printf '%q ' "$@")")"
  (cd "${work_dir}" && bash -lc "${inner}")
}

cmd_shell() {
  require_native_prefix
  local work_dir="${1:-.}"
  work_dir="$(abs_path "${work_dir}")"
  if [[ ! -d "${work_dir}" ]]; then
    echo "Directory not found: ${work_dir}" >&2
    exit 1
  fi
  local inner
  inner="$(openfoam_interactive_shell_cmd "openfoam" "${OPENFOAM_BASHRC}")"
  (cd "${work_dir}" && exec bash -lc "${inner}")
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
  native_run "${RUN_WORK_DIR}" "${RUN_CMD[@]}"
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

  native_run "$(pwd)" "$@"
}

native_main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
  env) cmd_env "$@" ;;
  env-path) cmd_env_path "$@" ;;
  completion) cmd_completion "$@" ;;
  run) cmd_run "$@" ;;
  shell) cmd_shell "$@" ;;
  -h | --help | help | "") usage ;;
  *) cmd_exec "${cmd}" "$@" ;;
  esac
}
