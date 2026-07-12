#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

_bundle_override="${OPENFOAM_BUNDLE_RUNTIME+x}"
_saved_bundle="${OPENFOAM_BUNDLE_RUNTIME-}"
openfoam_load_build_paths "${ROOT}"
if [[ -n "${_bundle_override}" ]]; then
  export OPENFOAM_BUNDLE_RUNTIME="${_saved_bundle}"
else
  export OPENFOAM_BUNDLE_RUNTIME="${OPENFOAM_BUNDLE_RUNTIME:-0}"
fi

FORCE_STAGE="${FORCE_STAGE:-0}"

OPENFOAM_STAGE="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_STAGE}")"
CPACK_DIR="${CPACK_DIR:-${ROOT}/${BUILD_CPACK_DIR:-build/cpack}}"
case "${CPACK_DIR}" in
/*) ;;
*) CPACK_DIR="${ROOT}/${CPACK_DIR}" ;;
esac

version="${OPENFOAM_VERSION:-v2412}"
version="${version#v}"
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
STAGE_STAMP="${OPENFOAM_STAGE}/.pack-stamp"

mkdir -p "${CPACK_DIR}"
archive="${CPACK_DIR}/openfoam-native-${version}-${os_name}-${arch}.tar.gz"

if [[ -f "${archive}" && -f "${STAGE_STAMP}" && "${archive}" -nt "${STAGE_STAMP}" ]] \
  && openfoam_pack_stamp_matches "${STAGE_STAMP}" "${OPENFOAM_BUNDLE_RUNTIME}"; then
  echo "[cpack] Up to date: ${archive}"
  ls -la "${archive}"
  exit 0
fi

FORCE_STAGE="${FORCE_STAGE}" bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"
bash "${ROOT}/scripts/install_openfoam_cli.sh" "${OPENFOAM_STAGE}"

echo "[cpack] Native install + CLI -> ${archive}"
tar -czf "${archive}" -C "${OPENFOAM_STAGE}" \
  --exclude='.DS_Store' \
  --exclude='*/.DS_Store' \
  --exclude='.stage-stamp' \
  --exclude='.pack-stamp' \
  --exclude='.dist-stamp' \
  .
ls -la "${archive}"
