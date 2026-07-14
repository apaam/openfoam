#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_BUILD="${1:?build dir required}"
OPENFOAM_STAGE="${2:?stage dir required}"

# Optional extra includes: space-separated paths, e.g. STAGE_EXTRA_INCLUDES="doc"
STAGE_EXTRA_INCLUDES="${STAGE_EXTRA_INCLUDES:-}"
FORCE_STAGE="${FORCE_STAGE:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

OF_DEST="${OPENFOAM_STAGE}/openfoam"

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[stage_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

if [[ "${FORCE_STAGE}" == "1" ]]; then
  echo "[stage_openfoam] Force refresh ${OF_DEST}/"
  openfoam_safe_rm "${OF_DEST}"
fi

mkdir -p "${OF_DEST}"

if [[ -f "${OF_DEST}/etc/bashrc" ]]; then
  echo "[stage_openfoam] Incremental sync ${OPENFOAM_BUILD}/ -> ${OF_DEST}/"
else
  echo "[stage_openfoam] Initial sync ${OPENFOAM_BUILD}/ -> ${OF_DEST}/"
fi

openfoam_rsync_install_tree "${OPENFOAM_BUILD}" "${OF_DEST}" "${STAGE_EXTRA_INCLUDES}"

while IFS= read -r dir; do
  if [[ ! -e "${OF_DEST}/${dir}" ]]; then
    echo "[stage_openfoam] Missing required path after stage: openfoam/${dir}" >&2
    exit 1
  fi
done < <(openfoam_install_paths "${STAGE_EXTRA_INCLUDES}")

date -u +%Y-%m-%dT%H:%M:%SZ > "${OPENFOAM_STAGE}/.stage-stamp"
echo "[stage_openfoam] Install tree ready at ${OF_DEST}"
