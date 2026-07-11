#!/usr/bin/env bash
set -euo pipefail

ROOT="/build/openfoam"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPENFOAM_ROOT="${ROOT}"
export OPENFOAM_BUILD="${ROOT}/build/openfoam"
export CACHE_BUILD="/cache/openfoam/build/openfoam"
export OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}"
export NUM_JOBS="${NUM_JOBS:-$(nproc)}"
export PLATFORM=linux

bash "${ROOT}/scripts/build_openfoam.sh"
bash "${SCRIPT_DIR}/stage_openfoam.sh" "${ROOT}/build/openfoam" "/build/stage/openfoam"
bash "${SCRIPT_DIR}/resolve_runtime_apt.sh" \
  /build/stage/openfoam /build/stage/openfoam.runtime-apt.txt
