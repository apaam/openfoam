#!/usr/bin/env bash
# Install openfoam CLI.
# Usage:
#   install_openfoam_cli.sh <cli_root>              # bundled: CLI inside OpenFOAM prefix (cpack)
#   install_openfoam_cli.sh <cli_root> <prefix>     # separate: CLI root + OpenFOAM WM_PROJECT_DIR
set -euo pipefail

CLI_ROOT="${1:?cli root required}"
NATIVE_PREFIX="${2:-${CLI_ROOT}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${CLI_ROOT}" in
/*) ;;
*) CLI_ROOT="${ROOT}/${CLI_ROOT}" ;;
esac
case "${NATIVE_PREFIX}" in
/*) ;;
*) NATIVE_PREFIX="${ROOT}/${NATIVE_PREFIX}" ;;
esac

CLI_SRC="${ROOT}/cli/openfoam"
SHARE_CLI="${CLI_ROOT}/share/openfoam/cli"
BUNDLED=false
if [[ "${CLI_ROOT}" == "${NATIVE_PREFIX}" ]]; then
  BUNDLED=true
fi

rm -rf "${SHARE_CLI}"
mkdir -p "${SHARE_CLI}"
for script in openfoam.sh prefix.sh native.sh dev_tree.sh docker_run.sh shell_prompt.sh \
  shell_bashrc.sh _openfoam completion.bash completion.zsh rewrite_openfoam_paths.sh; do
  src="${CLI_SRC}/${script}"
  [[ "${script}" == rewrite_openfoam_paths.sh ]] && src="${ROOT}/docker/rewrite_openfoam_paths.sh"
  cp "${src}" "${SHARE_CLI}/${script}"
  chmod +x "${SHARE_CLI}/${script}"
done

mkdir -p "${CLI_ROOT}/bin"
if [[ "${BUNDLED}" == true ]]; then
  cat >"${CLI_ROOT}/bin/openfoam" <<'EOF'
#!/usr/bin/env bash
OPENFOAM_PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPENFOAM_PREFIX
exec bash "${OPENFOAM_PREFIX}/share/openfoam/cli/openfoam.sh" "$@"
EOF
else
  printf '%s\n' "$(cd "${NATIVE_PREFIX}" && pwd)" >"${CLI_ROOT}/.openfoam-prefix"
  cat >"${CLI_ROOT}/bin/openfoam" <<'EOF'
#!/usr/bin/env bash
CLI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${OPENFOAM_PREFIX:-}" ]]; then
  OPENFOAM_PREFIX="$(<"${CLI_ROOT}/.openfoam-prefix")"
fi
export OPENFOAM_PREFIX
exec bash "${CLI_ROOT}/share/openfoam/cli/openfoam.sh" "$@"
EOF
fi
chmod +x "${CLI_ROOT}/bin/openfoam"

ZSH_COMP_DIR="${CLI_ROOT}/share/zsh/site-functions"
BASH_COMP_DIR="${CLI_ROOT}/share/bash-completion/completions"
mkdir -p "${ZSH_COMP_DIR}" "${BASH_COMP_DIR}"
cp "${CLI_SRC}/_openfoam" "${ZSH_COMP_DIR}/_openfoam"
cat >"${BASH_COMP_DIR}/openfoam" <<EOF
OPENFOAM_PACKAGE_DIR="${SHARE_CLI}"
export OPENFOAM_PACKAGE_DIR
source "\${OPENFOAM_PACKAGE_DIR}/completion.bash"
EOF

if [[ "${BUNDLED}" == true ]]; then
  echo "[install_openfoam_cli] Bundled CLI -> ${CLI_ROOT}/bin/openfoam"
else
  echo "[install_openfoam_cli] CLI -> ${CLI_ROOT}/bin/openfoam (prefix=${NATIVE_PREFIX})"
fi
