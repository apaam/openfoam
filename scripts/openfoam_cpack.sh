#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
load_make_config "${ROOT}"

FORCE_STAGE="${FORCE_STAGE:-0}"

install_cpack_cli() {
  local stage="$1"
  local cli_src="${ROOT}/cli/openfoam_cli"
  local share_cli="${stage}/share/openfoam/cli"

  mkdir -p "${share_cli}"
  for script in openfoam.sh prefix.sh native.sh docker_run.sh; do
    cp "${cli_src}/${script}" "${share_cli}/${script}"
    chmod +x "${share_cli}/${script}"
  done

  mkdir -p "${stage}/bin"
  cat > "${stage}/bin/openfoam" <<'EOF'
#!/usr/bin/env bash
OPENFOAM_PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OPENFOAM_PREFIX
exec bash "${OPENFOAM_PREFIX}/share/openfoam/cli/openfoam.sh" "$@"
EOF
  chmod +x "${stage}/bin/openfoam"
}

OPENFOAM_STAGE="${OPENFOAM_STAGE:-${ROOT}/build/stage/openfoam}"
case "${OPENFOAM_STAGE}" in
/*) ;;
*) OPENFOAM_STAGE="${ROOT}/${OPENFOAM_STAGE}" ;;
esac
CPACK_DIR="${CPACK_DIR:-${ROOT}/${BUILD_CPACK_DIR:-build/cpack}}"
case "${CPACK_DIR}" in
/*) ;;
*) CPACK_DIR="${ROOT}/${CPACK_DIR}" ;;
esac

version="${OPENFOAM_VERSION:-v2412}"
version="${version#v}"
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
STAGE_STAMP="${OPENFOAM_STAGE}/.stage-stamp"

mkdir -p "${CPACK_DIR}"
archive="${CPACK_DIR}/openfoam-native-${version}-${os_name}-${arch}.tar.gz"

if [[ -f "${archive}" && -f "${STAGE_STAMP}" && "${archive}" -nt "${STAGE_STAMP}" ]]; then
  echo "[cpack] Up to date: ${archive}"
  ls -la "${archive}"
  exit 0
fi

FORCE_STAGE="${FORCE_STAGE}" bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"
install_cpack_cli "${OPENFOAM_STAGE}"

echo "[cpack] Native install + CLI -> ${archive}"
tar -czf "${archive}" -C "${OPENFOAM_STAGE}" .
ls -la "${archive}"
