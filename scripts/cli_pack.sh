#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

CLI_BUILD="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_CLI_BUILD}")"
OPENFOAM_BUILD="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_BUILD}")"
PACK_DIR="${PACK_DIR:-${ROOT}/${BUILD_CLI_PACK_DIR:-build/cli-pack}}"
case "${PACK_DIR}" in
/*) ;;
*) PACK_DIR="${ROOT}/${PACK_DIR}" ;;
esac

version="${OPENFOAM_VERSION:-v2412}"
version="${version#v}"
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
stamp="${CLI_BUILD}/share/openfoam/cli/manifest.json"

mkdir -p "${PACK_DIR}"
archive="${PACK_DIR}/openfoam-cli-${version}-${os_name}-${arch}.tar.gz"

if [[ ! -x "${CLI_BUILD}/bin/openfoam" ]]; then
  OPENFOAM_VERSION="${OPENFOAM_VERSION:-v${version}}" \
    bash "${ROOT}/scripts/install_openfoam_cli.sh" "${CLI_BUILD}" "${OPENFOAM_BUILD}"
fi

# shellcheck source=../cli/openfoam/manifest.sh
source "${ROOT}/cli/openfoam/manifest.sh"
write_cli_manifest "${CLI_BUILD}/share/openfoam/cli/manifest.json" "pack" 0 "${version}"
stamp="${CLI_BUILD}/share/openfoam/cli/manifest.json"

if [[ -f "${archive}" && -f "${stamp}" && "${archive}" -nt "${stamp}" ]]; then
  echo "[cli-pack] Up to date: ${archive}"
  ls -la "${archive}"
  exit 0
fi

echo "[cli-pack] CLI -> ${archive}"
mkdir -p "$(dirname "${archive}")"
tar -czf "${archive}" -C "${CLI_BUILD}" \
  --exclude='.DS_Store' \
  --exclude='*/.DS_Store' \
  .
ls -la "${archive}"
