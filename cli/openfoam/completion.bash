# Bash tab completion for the openfoam CLI.
# Pip install registers share/bash-completion/completions/openfoam automatically.
# Or source this file from shell_bashrc.sh inside openfoam shell.

_openfoam_complete_dirs() {
  compgen -d -- "$1"
}

_openfoam_complete_paths() {
  compgen -f -- "$1"
}

_openfoam() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "${COMP_CWORD}" in
  1)
    mapfile -t COMPREPLY < <(
      compgen -W "prefix dev run shell docker completion help -h --help" -- "${cur}"
    )
    ;;
  *)
    case "${COMP_WORDS[1]}" in
    prefix | help | -h | --help)
      ;;
    dev)
      if [[ "${COMP_CWORD}" -eq 2 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "install clean help -h --help" -- "${cur}")
      fi
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
          compgen -W "run shell pull install-image uninstall-image help -h --help" -- "${cur}"
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
        esac
        ;;
      esac
      ;;
    esac
    ;;
  esac
}

if ! declare -F _openfoam >/dev/null 2>&1; then
  complete -o default -o bashdefault -F _openfoam openfoam
fi
