#!/usr/bin/env bash
# Stage wheel into DIST_DIR for dist-native / dist-docker.
# Usage:
#   DIST_DIR=... stage_cli_dist.sh
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

mkdir -p "${DIST_DIR}"

wheel="$(ls -t "${WHEEL_DIR}"/${WHEEL_MATCH} 2>/dev/null | head -1 || true)"
if [[ -z "${wheel}" ]]; then
  printf '[stage-dist] Wheel not found under %s; run make wheel first\n' \
    "${WHEEL_DIR}" >&2
  exit 1
fi

cp "${wheel}" "${DIST_DIR}/"
printf '[stage-dist] wheel -> %s/%s\n' "${DIST_DIR}" "$(basename "${wheel}")"
