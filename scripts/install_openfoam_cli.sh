#!/usr/bin/env bash
# Install phynexis-foam CLI.
# Usage:
#   install_openfoam_cli.sh <cli_root>              # CLI inside product prefix
#   install_openfoam_cli.sh <cli_root> <of_prefix>  # CLI root + OpenFOAM WM_PROJECT_DIR
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

CLI_SRC="${ROOT}/cli/phynexis_foam"
SHARE_CLI="${CLI_ROOT}/share/phynexis-foam/cli"
PRODUCT_LAYOUT=false
if [[ -f "${CLI_ROOT}/openfoam/etc/bashrc" ]] \
  || [[ "${NATIVE_PREFIX}" == "${CLI_ROOT}/openfoam" ]]; then
  PRODUCT_LAYOUT=true
fi

rm -rf "${SHARE_CLI}"
mkdir -p "${SHARE_CLI}"
for script in phynexis-foam.sh prefix.sh native.sh docker_run.sh shell_prompt.sh \
  shell_bashrc.sh _phynexis-foam completion.bash completion.zsh rewrite_openfoam_paths.sh manifest.sh; do
  src="${CLI_SRC}/${script}"
  [[ "${script}" == rewrite_openfoam_paths.sh ]] && src="${ROOT}/scripts/rewrite_openfoam_paths.sh"
  cp "${src}" "${SHARE_CLI}/${script}"
  chmod +x "${SHARE_CLI}/${script}"
done

mkdir -p "${CLI_ROOT}/bin"
if [[ "${PRODUCT_LAYOUT}" == true || "${CLI_ROOT}" == "${NATIVE_PREFIX}" ]]; then
  # Product pack or self-contained prefix: OPENFOAM_PREFIX = CLI root.
  cat >"${CLI_ROOT}/bin/phynexis-foam" <<'EOF'
#!/usr/bin/env bash
OPENFOAM_PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPENFOAM_PREFIX
exec bash "${OPENFOAM_PREFIX}/share/phynexis-foam/cli/phynexis-foam.sh" "$@"
EOF
else
  # Dev: CLI in cli-build/, OpenFOAM in openfoam-build/.
  cat >"${CLI_ROOT}/bin/phynexis-foam" <<EOF
#!/usr/bin/env bash
CLI_ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
: "\${OPENFOAM_PREFIX:=${NATIVE_PREFIX}}"
export OPENFOAM_PREFIX
exec bash "\${CLI_ROOT}/share/phynexis-foam/cli/phynexis-foam.sh" "\$@"
EOF
fi
chmod +x "${CLI_ROOT}/bin/phynexis-foam"

ZSH_COMP_DIR="${CLI_ROOT}/share/zsh/site-functions"
BASH_COMP_DIR="${CLI_ROOT}/share/bash-completion/completions"
mkdir -p "${ZSH_COMP_DIR}" "${BASH_COMP_DIR}"
cp "${CLI_SRC}/_phynexis-foam" "${ZSH_COMP_DIR}/_phynexis-foam"
# Drop pre-rename launchers/completions from older installs.
rm -f "${CLI_ROOT}/bin/openfoam" \
  "${ZSH_COMP_DIR}/_openfoam" \
  "${BASH_COMP_DIR}/openfoam"
cat >"${BASH_COMP_DIR}/phynexis-foam" <<EOF
OPENFOAM_PACKAGE_DIR="${SHARE_CLI}"
export OPENFOAM_PACKAGE_DIR
source "\${OPENFOAM_PACKAGE_DIR}/completion.bash"
EOF

if [[ "${PRODUCT_LAYOUT}" == true ]] || [[ "${CLI_ROOT}" == "${NATIVE_PREFIX}" ]]; then
  # shellcheck source=../cli/phynexis_foam/manifest.sh
  source "${ROOT}/cli/phynexis_foam/manifest.sh"
  write_cli_manifest "${SHARE_CLI}/manifest.json" "pack" 0 \
    "${OPENFOAM_VERSION#v}"
  echo "[install_openfoam_cli] Bundled CLI -> ${CLI_ROOT}/bin/phynexis-foam"
else
  # shellcheck source=../cli/phynexis_foam/manifest.sh
  source "${ROOT}/cli/phynexis_foam/manifest.sh"
  write_cli_manifest "${SHARE_CLI}/manifest.json" "dev" 0 \
    "${OPENFOAM_VERSION#v}"
  echo "[install_openfoam_cli] CLI -> ${CLI_ROOT}/bin/phynexis-foam (prefix=${NATIVE_PREFIX})"
fi
