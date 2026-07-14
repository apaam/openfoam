#!/usr/bin/env bash
# Stage wheel (+ optional host CLI pack) into DIST_DIR for dist-native / dist-docker.
# Usage:
#   DIST_DIR=... stage_cli_dist.sh           # copy wheel only
#   DIST_DIR=... HOST_CLI_PACK=1 stage_cli_dist.sh  # wheel + host CLI tar
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

DIST_DIR="${DIST_DIR:?DIST_DIR required}"
case "${DIST_DIR}" in
/*) ;;
*) DIST_DIR="${ROOT}/${DIST_DIR}" ;;
esac

WHEEL_DIR="$(openfoam_abs_under_root "${ROOT}" "${BUILD_WHEEL_DIR}")"
WHEEL_MATCH="${BUILD_WHEEL_MATCH:-openfoam_cli-*.whl}"
HOST_CLI_PACK="${HOST_CLI_PACK:-0}"

mkdir -p "${DIST_DIR}"

wheel="$(ls -t "${WHEEL_DIR}"/${WHEEL_MATCH} 2>/dev/null | head -1 || true)"
if [[ -z "${wheel}" ]]; then
  printf '[stage-dist] Wheel not found under %s; run make wheel first\n' \
    "${WHEEL_DIR}" >&2
  exit 1
fi

cp "${wheel}" "${DIST_DIR}/"
printf '[stage-dist] wheel -> %s/%s\n' "${DIST_DIR}" "$(basename "${wheel}")"

if [[ "${HOST_CLI_PACK}" =~ ^(1|yes|true|on)$ ]]; then
  OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}" \
    PACK_DIR="${DIST_DIR}" \
    bash "${ROOT}/scripts/cli_pack.sh"
fi
