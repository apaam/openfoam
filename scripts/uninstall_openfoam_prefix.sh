#!/usr/bin/env bash
# Remove make install product under INSTALL_PREFIX using .openfoam-manifest.json.
# Usage: uninstall_openfoam_prefix.sh
# Env: INSTALL_PREFIX (required via make/config), FORCE=1 for no-manifest fallback.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"
# shellcheck source=openfoam_install_manifest.sh
source "${ROOT}/scripts/openfoam_install_manifest.sh"

openfoam_load_build_paths "${ROOT}"

PREFIX="${INSTALL_PREFIX:-install}"
PREFIX="$(openfoam_abs_under_root "${ROOT}" "${PREFIX}")"

openfoam_uninstall_install_prefix "${PREFIX}" "${FORCE:-0}"
