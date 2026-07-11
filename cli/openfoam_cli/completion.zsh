# Zsh tab completion for the openfoam CLI.
# Enable: eval "$(openfoam completion zsh)"
# Requires compinit (usually already enabled in interactive zsh).

typeset -ga _openfoam_apps_cache

_openfoam_cli_dir() {
  if [[ -n ${OPENFOAM_CLI_DIR:-} ]]; then
    print -r -- "${OPENFOAM_CLI_DIR}"
  else
    print -r -- "${${(%):-%x}:A:h}"
  fi
}

_openfoam_resolve_prefix() {
  if [[ -n ${OPENFOAM_PREFIX:-} && -f ${OPENFOAM_PREFIX}/etc/bashrc ]]; then
    print -r -- "${OPENFOAM_PREFIX}"
    return 0
  fi

  local cli_dir
  cli_dir="$(_openfoam_cli_dir)"
  bash -c 'source "'"${cli_dir}"'/prefix.sh" && resolve_openfoam_prefix' 2>/dev/null
}

_openfoam_refresh_apps() {
  local prefix="$1"
  local -a apps=()
  local bin_dir app_path

  _openfoam_apps_cache=()
  [[ -n ${prefix} ]] || return 1

  for bin_dir in "${prefix}/bin" ${prefix}/platforms/*/bin(N/); do
    for app_path in ${bin_dir}/*(N); do
      [[ -x ${app_path} ]] || continue
      [[ ${app_path:t} == openfoam ]] && continue
      apps+=("${app_path:t}")
    done
  done

  _openfoam_apps_cache=(${(u)apps})
  (( ${#_openfoam_apps_cache[@]} ))
}

_openfoam_load_apps() {
  if (( ${#_openfoam_apps_cache[@]} )); then
    return 0
  fi

  local prefix
  prefix="$(_openfoam_resolve_prefix 2>/dev/null)" || return 1
  _openfoam_refresh_apps "${prefix}"
}

_openfoam_is_native_subcmd() {
  case "$1" in
  env | run | shell | docker | completion | help | -h | --help) return 0 ;;
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
  _files -/
}

_openfoam_complete_paths() {
  _files
}

_openfoam_delegate_app_complete() {
  local app="$1"

  if whence _of_complete_ >/dev/null 2>&1; then
    emulate -L sh
    COMP_WORDS=("${words[@]}")
    COMP_CWORD="${CURRENT}"
    COMPREPLY=()
    _of_complete_ "${app}" "${words[CURRENT]}" "${words[CURRENT - 1]}"
    if (( ${#COMPREPLY[@]} )); then
      compadd -a COMPREPLY
      return 0
    fi
  fi

  _files
}

_openfoam() {
  local curcontext="$curcontext" ret=1
  local -a static apps docker_static

  if (( CURRENT == 2 )); then
    static=(env run shell docker completion help -h --help)
    if _openfoam_load_apps; then
      apps=(${_openfoam_apps_cache[@]})
      _describe 'openfoam command' static
      _describe 'OpenFOAM application' apps
    else
      _describe 'openfoam command' static
    fi
    return 0
  fi

  case ${words[2]} in
  env | help | -h | --help)
    ;;
  completion)
    if (( CURRENT == 3 )); then
      _values 'shell type' bash zsh
    fi
    ;;
  shell)
    if (( CURRENT == 3 )); then
      _openfoam_complete_dirs
    fi
    ;;
  run)
    if (( CURRENT == 3 )); then
      _openfoam_complete_paths
    fi
    ;;
  docker)
    case ${CURRENT} in
    3)
      docker_static=(
        run shell pull install-image uninstall-image help -h --help
      )
      if _openfoam_load_apps; then
        apps=(${_openfoam_apps_cache[@]})
        _describe 'docker command' docker_static
        _describe 'OpenFOAM application' apps
      else
        _describe 'docker command' docker_static
      fi
      ;;
    4)
      case ${words[3]} in
      shell)
        _openfoam_complete_dirs
        ;;
      run)
        _openfoam_complete_paths
        ;;
      install-image)
        _files -g '*.tar.gz' -g '*.tgz' -g '*.tar'
        ;;
      pull | uninstall-image | help | -h | --help)
        ;;
      *)
        if ! _openfoam_is_docker_subcmd "${words[3]}"; then
          _openfoam_delegate_app_complete "${words[3]}"
        fi
        ;;
      esac
      ;;
    *)
      if ! _openfoam_is_docker_subcmd "${words[3]}"; then
        _openfoam_delegate_app_complete "${words[3]}"
      fi
      ;;
    esac
    ;;
  *)
    if ! _openfoam_is_native_subcmd "${words[2]}"; then
      _openfoam_delegate_app_complete "${words[2]}"
    fi
    ;;
  esac
}

_openfoam_enable_app_completions() {
  local project_dir completion_file bash_env

  project_dir="${WM_PROJECT_DIR:-$(_openfoam_resolve_prefix 2>/dev/null)}"
  [[ -n ${project_dir} ]] || return 0

  completion_file="${project_dir}/etc/config.sh/bash_completion"
  [[ -f ${completion_file} ]] || return 0

  if whence _of_complete_ >/dev/null 2>&1; then
    return 0
  fi

  autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null

  if [[ -z ${FOAM_APPBIN:-} ]]; then
    bash_env="$(
      bash -c 'source "'"${project_dir}"'/etc/bashrc" >/dev/null 2>&1 || exit 1
printf "WM_PROJECT_DIR=%q\nFOAM_APPBIN=%q\n" "$WM_PROJECT_DIR" "$FOAM_APPBIN"'
    )" || return 0
    eval "${bash_env}"
  fi

  export WM_PROJECT_DIR="${project_dir}"
  emulate -L sh
  BASH_VERSINFO=(5 3 0 0 0 0)
  # shellcheck disable=SC1090
  source "${completion_file}"
}

_openfoam_enable_app_completions

autoload -Uz compdef
compdef _openfoam openfoam
