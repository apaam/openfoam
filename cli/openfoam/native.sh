#!/usr/bin/env bash
# Native OpenFOAM launcher (openfoam prefix / run / shell).

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
  openfoam_source_bashrc_cmd "${OPENFOAM_BASHRC}" "${inner}"
}

usage() {
  cat <<EOF
${CLI_PREFIX} — native OpenFOAM commands

  prefix [--path]                   Print OPENFOAM_PREFIX (resolved install root)
  completion bash|zsh               Tab completion

Set OPENFOAM_PREFIX to your install root; source <prefix>/etc/bashrc to load the env.

Install:
  install <archive.tar.gz> [--prefix <dir>] [--force]
                                    Install a native pack (default prefix: ${DEFAULT_OPENFOAM_PREFIX})

Run:
  run [-np <N>] <command> [args...] Run a command in the current directory
  shell [dir]                       Interactive shell (sources etc/bashrc)

Examples:
  pip install openfoam_cli-*.whl
  openfoam install openfoam-*.tar.gz
  export OPENFOAM_PREFIX=${DEFAULT_OPENFOAM_PREFIX}
  source "\$OPENFOAM_PREFIX/etc/bashrc"
  blockMesh -help
  openfoam run blockMesh
  openfoam run -np 4 icoFoam -parallel
  openfoam run ./Allrun
  openfoam shell .
EOF
}

cmd_prefix() {
  local prefix="" bare=false

  while (("$#" > 0)); do
    case "$1" in
    --path | -p)
      bare=true
      shift
      ;;
    *)
      echo "Usage: ${CLI_PREFIX} prefix [--path]" >&2
      exit 1
      ;;
    esac
  done

  prefix="$(resolve_runtime_prefix)"
  if ! prefix_has_bashrc "${prefix}"; then
    prefix_hint_missing_bashrc "${prefix}"
  fi
  if [[ "${bare}" == true ]]; then
    printf '%s\n' "${prefix}"
  else
    printf 'OPENFOAM_PREFIX=%q\n' "${prefix}"
  fi
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
    sed '/^#compdef /d' "${SCRIPT_DIR}/_openfoam"
    printf '\nautoload -Uz compdef\ncompdef _openfoam openfoam\n'
    ;;
  *)
    echo "Unsupported shell: ${shell} (supported: bash, zsh)" >&2
    exit 1
    ;;
  esac
}

cmd_install() {
  local archive="" prefix="${DEFAULT_OPENFOAM_PREFIX}" force=0

  while (("$#" > 0)); do
    case "$1" in
    --prefix | -p)
      if (("$#" < 2)); then
        echo "Missing value for $1" >&2
        exit 1
      fi
      prefix="$2"
      shift 2
      ;;
    --force | -f)
      force=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${archive}" ]]; then
        archive="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
    esac
  done

  if [[ -z "${archive}" ]]; then
    echo "Usage: ${CLI_PREFIX} install <archive.tar.gz> [--prefix <dir>] [--force]" >&2
    exit 1
  fi
  if [[ ! -f "${archive}" ]]; then
    echo "Archive not found: ${archive}" >&2
    exit 1
  fi
  case "${archive}" in
  *.tar.gz | *.tgz) ;;
  *)
    echo "Expected a .tar.gz native pack: ${archive}" >&2
    exit 1
    ;;
  esac
  archive="$(abs_path "${archive}")"

  if [[ -f "${prefix}/etc/bashrc" && "${force}" -ne 1 ]]; then
    echo "Already installed at ${prefix} (etc/bashrc exists); use --force to overwrite." >&2
    exit 1
  fi

  # Empty SUDO means the target is user-writable; bash 3.2 safe (no arrays).
  local SUDO="" parent="${prefix}"
  while [[ ! -d "${parent}" ]]; do parent="$(dirname "${parent}")"; done
  if [[ -d "${prefix}" ]]; then
    [[ -w "${prefix}" ]] || SUDO="sudo"
  else
    [[ -w "${parent}" ]] || SUDO="sudo"
  fi

  echo "[install] ${archive} -> ${prefix}"
  ${SUDO} mkdir -p "${prefix}"
  ${SUDO} tar -xzf "${archive}" -C "${prefix}"

  # Relocate paths baked in at pack time to the actual install root.
  local marker="${prefix}/.pack-source-prefix" old="" new="" rewrite=""
  if [[ -f "${marker}" ]]; then
    if ! rewrite="$(rewrite_script_path)"; then
      echo "Install failed: rewrite_openfoam_paths.sh not found beside the CLI" >&2
      exit 1
    fi
    old="$(${SUDO} cat "${marker}")"
    new="$(cd "${prefix}" && pwd)"
    if [[ -n "${old}" && "${old}" != "${new}" ]]; then
      # Product layout nests OF under openfoam/; legacy packs are flat.
      local of_tree="${prefix}/openfoam"
      [[ -f "${of_tree}/etc/bashrc" ]] || of_tree="${prefix}"
      ${SUDO} bash "${rewrite}" "${of_tree}" "${old}" "${new}"
    fi
    printf '%s\n' "${new}" | ${SUDO} tee "${prefix}/${REWRITE_MARKER}" >/dev/null
  fi

  if ! prefix_has_bashrc "${prefix}"; then
    echo "Install failed: ${prefix}/etc/bashrc (or openfoam/etc/bashrc) missing" >&2
    exit 1
  fi

  cat <<EOF
[install] Done at ${prefix}

Load the environment:
  export OPENFOAM_PREFIX=${prefix}
  source "\$OPENFOAM_PREFIX/etc/bashrc"

Or call the bundled CLI:
  ${prefix}/bin/openfoam run blockMesh
EOF
}

native_run_in_dir() {
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
  inner="$(openfoam_shell_cmd "$(openfoam_interactive_shell_cmd "openfoam")")"
  (cd "${work_dir}" && exec bash -lc "${inner}")
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
  native_run_in_dir "${RUN_WORK_DIR}" "${RUN_CMD[@]}"
}

unknown_cmd() {
  local cmd="$1"
  echo "Unknown command: ${cmd}" >&2
  echo "Run: ${CLI_PREFIX} help" >&2
  exit 1
}

native_main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
  prefix) cmd_prefix "$@" ;;
  completion) cmd_completion "$@" ;;
  install) cmd_install "$@" ;;
  run) cmd_run "$@" ;;
  shell) cmd_shell "$@" ;;
  -h | --help | help | "") usage ;;
  *) unknown_cmd "${cmd}" ;;
  esac
}
