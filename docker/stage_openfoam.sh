#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_BUILD="${1:-/build/openfoam/build}"
OPENFOAM_STAGE="${2:-/build/stage/openfoam}"

# Optional extra excludes: space-separated paths, e.g. STAGE_EXTRA_EXCLUDES="tutorials doc"
STAGE_EXTRA_EXCLUDES="${STAGE_EXTRA_EXCLUDES:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=openfoam_install_excludes.sh
source "${SCRIPT_DIR}/openfoam_install_excludes.sh"

RSYNC_EXCLUDES=("${OPENFOAM_INSTALL_EXCLUDES[@]}")
for path in ${STAGE_EXTRA_EXCLUDES}; do
  RSYNC_EXCLUDES+=(--exclude="${path}")
done

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[stage_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

rm -rf "${OPENFOAM_STAGE}"
mkdir -p "${OPENFOAM_STAGE}"

echo "[stage_openfoam] ${OPENFOAM_BUILD}/ -> ${OPENFOAM_STAGE}/"
rsync -a "${RSYNC_EXCLUDES[@]}" "${OPENFOAM_BUILD}/" "${OPENFOAM_STAGE}/"

for dir in "${OPENFOAM_INSTALL_REQUIRED[@]}"; do
  if [[ ! -d "${OPENFOAM_STAGE}/${dir}" ]]; then
    echo "[stage_openfoam] Missing required dir after stage: ${dir}" >&2
    exit 1
  fi
done

echo "[stage_openfoam] Install tree ready at ${OPENFOAM_STAGE}"
