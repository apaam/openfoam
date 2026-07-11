#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENFOAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

cd "${ROOT}"
git submodule sync
git submodule update --depth 1 --init

export OPENFOAM_ROOT="${ROOT}"
bash "${ROOT}/scripts/prune_openfoam_submodules.sh"
