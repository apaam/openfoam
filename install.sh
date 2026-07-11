#!/usr/bin/env bash
# Local entry: ./install.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPENFOAM_ROOT="${OPENFOAM_ROOT:-${ROOT}}"
export OPENFOAM_VERSION="${1:-${OPENFOAM_VERSION:-v2412}}"

bash "${ROOT}/scripts/build_openfoam.sh"

# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
load_make_config "${ROOT}"

OPENFOAM_CLI_BUILD="${OPENFOAM_CLI_BUILD:-build/cli}"
OPENFOAM_BUILD="${OPENFOAM_BUILD:-build/openfoam}"
bash "${ROOT}/scripts/install_openfoam_cli.sh" \
  "${ROOT}/${OPENFOAM_CLI_BUILD}" "${ROOT}/${OPENFOAM_BUILD}"
