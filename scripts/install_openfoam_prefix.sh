#!/usr/bin/env bash
# Install product tree from openfoam-build into INSTALL_PREFIX.
# Stages etc/ + openfoam/ + embedded CLI (same layout as pack); does not use pack/ or wheel/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

PREFIX="${INSTALL_PREFIX:-install}"
PREFIX="$(openfoam_abs_under_root "${ROOT}" "${PREFIX}")"
OPENFOAM_BUILD="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_BUILD}")"

if [[ ! -f "${OPENFOAM_BUILD}/etc/bashrc" ]]; then
  echo "[install] Missing ${OPENFOAM_BUILD}/etc/bashrc; run make openfoam (or make all) first" >&2
  exit 1
fi

# shellcheck source=openfoam_install_manifest.sh
source "${ROOT}/scripts/openfoam_install_manifest.sh"

echo "[install] ${OPENFOAM_BUILD} -> ${PREFIX}"
FORCE_STAGE="${FORCE_STAGE:-0}" \
  OPENFOAM_INSTALL_MODE=1 \
  OPENFOAM_BUNDLE_RUNTIME="${OPENFOAM_BUNDLE_RUNTIME:-0}" \
  OPENFOAM_STAGE_OVERRIDE="${PREFIX}" \
  bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"

openfoam_write_install_manifest \
  "${PREFIX}" \
  "${OPENFOAM_BUNDLE_RUNTIME:-0}" \
  "${OPENFOAM_VERSION#v}"

echo "[install] Done at ${PREFIX}"
echo "[install] export OPENFOAM_PREFIX=${PREFIX}"
echo "[install] source \"\${OPENFOAM_PREFIX}/etc/bashrc\""
