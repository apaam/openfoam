#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
load_make_config "${ROOT}"

OPENFOAM_BUILD="${OPENFOAM_BUILD:-${ROOT}/build}"
OPENFOAM_STAGE="${OPENFOAM_STAGE:-${ROOT}/build/stage/openfoam}"

exec bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"
