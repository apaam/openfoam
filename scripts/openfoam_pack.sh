#!/usr/bin/env bash
# Build one openfoam-native-*.tar.gz (OF tree + embedded CLI) into PACK_DIR.
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
PACK_DIR="${PACK_DIR:-${ROOT}/${BUILD_PACK_DIR}}"
case "${PACK_DIR}" in
/*) ;;
*) PACK_DIR="${ROOT}/${PACK_DIR}" ;;
esac

version="${OPENFOAM_VERSION:-v2412}"
version="${version#v}"
os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
STAGE_STAMP="${OPENFOAM_STAGE}/.pack-stamp"

mkdir -p "${PACK_DIR}"
archive="${PACK_DIR}/openfoam-native-${version}-${os_name}-${arch}.tar.gz"

if [[ -f "${archive}" && -f "${STAGE_STAMP}" && "${archive}" -nt "${STAGE_STAMP}" ]] \
  && openfoam_pack_stamp_matches "${STAGE_STAMP}" "${OPENFOAM_BUNDLE_RUNTIME}" \
  && [[ -f "${OPENFOAM_STAGE}/etc/bashrc" ]] \
  && [[ -f "${OPENFOAM_STAGE}/openfoam/etc/bashrc" ]] \
  && [[ -x "${OPENFOAM_STAGE}/bin/openfoam" ]] \
  && [[ ! -d "${OPENFOAM_STAGE}/platforms" ]] \
  && [[ ! -d "${OPENFOAM_STAGE}/etc/config.sh" ]]; then
  echo "[pack] Up to date: ${archive}"
  ls -la "${archive}"
  exit 0
fi

FORCE_STAGE="${FORCE_STAGE}" bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"

echo "[pack] -> ${archive} (bundle=${OPENFOAM_BUNDLE_RUNTIME})"
openfoam_pack_prefix_tar "${OPENFOAM_STAGE}" "${archive}"
ls -la "${archive}"
