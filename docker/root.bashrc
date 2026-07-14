# Container interactive / docker-run env (installed as /root/.bashrc).
# Non-interactive `openfoam docker run` also sources this file explicitly.
# Product env: /opt/openfoam/etc/bashrc → openfoam/etc/bashrc.

if [[ -f /opt/openfoam/etc/bashrc ]]; then
  _of_had_u=0
  case "$-" in *u*) _of_had_u=1; set +u ;; esac
  _of_saved_args=("$@")
  set --
  # shellcheck disable=SC1091
  source /opt/openfoam/etc/bashrc
  set -- "${_of_saved_args[@]}"
  unset _of_saved_args
  [[ "${_of_had_u}" -eq 1 ]] && set -u
  unset _of_had_u
fi
