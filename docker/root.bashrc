# Container interactive / docker-run env (installed as /root/.bashrc).
# Non-interactive `openfoam docker run` also sources this file explicitly.
# Do not patch OpenFOAM etc/bashrc; activate bundled mpi-bin here.

if [[ -f /opt/openfoam/etc/bashrc ]]; then
  # OpenFOAM bashrc uses optional unset vars; tolerate callers with set -u.
  _of_had_u=0
  case "$-" in *u*) _of_had_u=1; set +u ;; esac
  # shellcheck disable=SC1091
  source /opt/openfoam/etc/bashrc
  [[ "${_of_had_u}" -eq 1 ]] && set -u
  unset _of_had_u
fi

if [[ -n "${WM_PROJECT_DIR:-}" && -d "${WM_PROJECT_DIR}/lib/bundled/mpi-bin" ]]; then
  case ":${PATH}:" in
  *":${WM_PROJECT_DIR}/lib/bundled/mpi-bin:"*) ;;
  *) export PATH="${WM_PROJECT_DIR}/lib/bundled/mpi-bin${PATH:+:$PATH}" ;;
  esac
fi
