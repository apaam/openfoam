# Bash tab completion for the openfoam CLI.
# Enable: eval "$(openfoam completion bash)"
# Or source this file from shell_bashrc.sh inside openfoam shell.

_openfoam_package_dir() {
  if [[ -n "${OPENFOAM_PACKAGE_DIR:-}" ]]; then
    printf '%s' "${OPENFOAM_PACKAGE_DIR}"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
  fi
}

_openfoam_resolve_prefix() {
  if [[ -n "${OPENFOAM_PREFIX:-}" && -f "${OPENFOAM_PREFIX}/etc/bashrc" ]]; then
    printf '%s' "${OPENFOAM_PREFIX}"
    return 0
  fi

  local cli_dir prefix_sh
  cli_dir="$(_openfoam_package_dir)"
  prefix_sh="${cli_dir}/prefix.sh"
  if [[ -f "${prefix_sh}" ]]; then
    # shellcheck disable=SC1090
    source "${prefix_sh}"
    resolve_openfoam_prefix 2>/dev/null
    return $?
  fi
  return 1
}

_openfoam_refresh_apps() {
  local prefix="$1"
  local -a apps=()
  local bin_dir app_path base

  _openfoam_apps_cache=""
  [[ -n "${prefix}" ]] || return 1

  for bin_dir in "${prefix}/bin" "${prefix}"/platforms/*/bin; do
    [[ -d "${bin_dir}" ]] || continue
    for app_path in "${bin_dir}"/*; do
      [[ -f "${app_path}" && -x "${app_path}" ]] || continue
      base="${app_path##*/}"
      [[ "${base}" == "openfoam" ]] && continue
      apps+=("${base}")
    done
  done

  if (("${#apps[@]}" > 0)); then
    _openfoam_apps_cache="$(printf '%s\n' "${apps[@]}" | sort -u | tr '\n' ' ')"
  fi
}

_openfoam_apps() {
  local cur="$1"
  local prefix

  if [[ -z "${_openfoam_apps_cache:-}" ]]; then
    prefix="$(_openfoam_resolve_prefix 2>/dev/null || true)"
    _openfoam_refresh_apps "${prefix}"
  fi

  if [[ -n "${_openfoam_apps_cache:-}" ]]; then
    compgen -W "${_openfoam_apps_cache}" -- "${cur}"
  fi
}

_openfoam_is_native_subcmd() {
  case "$1" in
  env | env-path | run | shell | docker | completion | help | -h | --help) return 0 ;;
  esac
  return 1
}

_openfoam_is_docker_subcmd() {
  case "$1" in
  run | shell | pull | install-image | uninstall-image | help | -h | --help) return 0 ;;
  esac
  return 1
}

_openfoam_complete_dirs() {
  compgen -d -- "$1"
}

_openfoam_complete_paths() {
  compgen -f -- "$1"
}

_openfoam_delegate_app_complete() {
  local app="$1"
  local cur="$2"
  local prev="$3"

  if declare -F _of_complete_ >/dev/null 2>&1; then
    _of_complete_ "${app}" "${cur}" "${prev}"
  else
    mapfile -t COMPREPLY < <(compgen -f -- "${cur}")
  fi
}

_openfoam() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "${COMP_CWORD}" in
  1)
    mapfile -t COMPREPLY < <(
      {
        compgen -W "env env-path run shell docker completion help -h --help" -- "${cur}"
        _openfoam_apps "${cur}"
      } | sort -u
    )
    ;;
  *)
    case "${COMP_WORDS[1]}" in
    env | env-path | help | -h | --help)
      ;;
    completion)
      if [[ "${COMP_CWORD}" -eq 2 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "bash zsh" -- "${cur}")
      fi
      ;;
    shell)
      if [[ "${COMP_CWORD}" -eq 2 ]]; then
        mapfile -t COMPREPLY < <(_openfoam_complete_dirs "${cur}")
      fi
      ;;
    run)
      if [[ "${COMP_CWORD}" -eq 2 ]]; then
        mapfile -t COMPREPLY < <(
          {
            _openfoam_complete_paths "${cur}"
            _openfoam_complete_dirs "${cur}"
          } | sort -u
        )
      fi
      ;;
    docker)
      case "${COMP_CWORD}" in
      2)
        mapfile -t COMPREPLY < <(
          {
            compgen -W "run shell pull install-image uninstall-image help -h --help" -- "${cur}"
            _openfoam_apps "${cur}"
          } | sort -u
        )
        ;;
      3)
        case "${COMP_WORDS[2]}" in
        shell)
          mapfile -t COMPREPLY < <(_openfoam_complete_dirs "${cur}")
          ;;
        run)
          mapfile -t COMPREPLY < <(
            {
              _openfoam_complete_paths "${cur}"
              _openfoam_complete_dirs "${cur}"
            } | sort -u
          )
          ;;
        install-image)
          mapfile -t COMPREPLY < <(
            compgen -f -X '!*.tar.gz' -- "${cur}"
            compgen -f -X '!*.tgz' -- "${cur}"
            compgen -f -X '!*.tar' -- "${cur}"
          )
          ;;
        pull | uninstall-image | help | -h | --help)
          ;;
        *)
          if ! _openfoam_is_docker_subcmd "${COMP_WORDS[2]}"; then
            _openfoam_delegate_app_complete "${COMP_WORDS[2]}" "${cur}" "${prev}"
          fi
          ;;
        esac
        ;;
      *)
        if ! _openfoam_is_docker_subcmd "${COMP_WORDS[2]}"; then
          _openfoam_delegate_app_complete "${COMP_WORDS[2]}" "${cur}" "${prev}"
        fi
        ;;
      esac
      ;;
    *)
      if ! _openfoam_is_native_subcmd "${COMP_WORDS[1]}"; then
        _openfoam_delegate_app_complete "${COMP_WORDS[1]}" "${cur}" "${prev}"
      fi
      ;;
    esac
    ;;
  esac
}

if ! declare -F _openfoam >/dev/null 2>&1; then
  complete -o default -o bashdefault -F _openfoam openfoam
fi

_openfoam_enable_app_completions() {
  local project_dir completion_file

  project_dir="${WM_PROJECT_DIR:-$(_openfoam_resolve_prefix 2>/dev/null || true)}"
  [[ -n "${project_dir}" ]] || return 0

  completion_file="${project_dir}/etc/config.sh/bash_completion"
  [[ -f "${completion_file}" ]] || return 0

  if declare -F _of_complete_ >/dev/null 2>&1; then
    return 0
  fi

  if [[ -z "${FOAM_APPBIN:-}" ]]; then
    # shellcheck disable=SC1090
    source "${project_dir}/etc/bashrc"
  else
    # shellcheck disable=SC1090
    source "${completion_file}"
  fi
}

_openfoam_enable_app_completions
