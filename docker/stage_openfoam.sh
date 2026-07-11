#!/usr/bin/env bash
set -euo pipefail

OPENFOAM_BUILD="${1:?build dir required}"
OPENFOAM_STAGE="${2:?stage dir required}"

# Optional extra includes: space-separated paths, e.g. STAGE_EXTRA_INCLUDES="doc"
STAGE_EXTRA_INCLUDES="${STAGE_EXTRA_INCLUDES:-}"
FORCE_STAGE="${FORCE_STAGE:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

if [[ ! -d "${OPENFOAM_BUILD}/etc" ]]; then
  echo "[stage_openfoam] Missing ${OPENFOAM_BUILD}/etc" >&2
  exit 1
fi

if [[ "${FORCE_STAGE}" == "1" ]]; then
  echo "[stage_openfoam] Force refresh ${OPENFOAM_STAGE}/"
  rm -rf "${OPENFOAM_STAGE}"
fi

mkdir -p "${OPENFOAM_STAGE}"

if [[ -f "${OPENFOAM_STAGE}/etc/bashrc" ]]; then
  echo "[stage_openfoam] Incremental sync ${OPENFOAM_BUILD}/ -> ${OPENFOAM_STAGE}/"
else
  echo "[stage_openfoam] Initial sync ${OPENFOAM_BUILD}/ -> ${OPENFOAM_STAGE}/"
fi

openfoam_rsync_install_tree "${OPENFOAM_BUILD}" "${OPENFOAM_STAGE}" "${STAGE_EXTRA_INCLUDES}"

while IFS= read -r dir; do
  if [[ ! -e "${OPENFOAM_STAGE}/${dir}" ]]; then
    echo "[stage_openfoam] Missing required path after stage: ${dir}" >&2
    exit 1
  fi
done < <(openfoam_install_paths "${STAGE_EXTRA_INCLUDES}")

date -u +%Y-%m-%dT%H:%M:%SZ > "${OPENFOAM_STAGE}/.stage-stamp"
echo "[stage_openfoam] Install tree ready at ${OPENFOAM_STAGE}"
