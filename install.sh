#!/usr/bin/env bash
# Local entry: ./install.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPENFOAM_ROOT="${OPENFOAM_ROOT:-${ROOT}}"
export OPENFOAM_VERSION="${1:-${OPENFOAM_VERSION:-v2412}}"

# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
openfoam_load_build_paths "${ROOT}"

bash "${ROOT}/scripts/build_openfoam.sh"
