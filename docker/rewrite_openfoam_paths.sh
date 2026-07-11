#!/usr/bin/env bash
# Rewrite staged OpenFOAM config paths for runtime install prefix.
# Mirrors phynexis-v0 docker/stage_openfoam_runtime.sh path handling.
set -euo pipefail

STAGE="${1:?stage dir required}"
OLD_PREFIX="${2:?old prefix required}"
NEW_PREFIX="${3:?new prefix required}"

if [[ ! -f "${STAGE}/etc/bashrc" ]]; then
  echo "[rewrite_openfoam_paths] Missing ${STAGE}/etc/bashrc" >&2
  exit 1
fi

sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

rewrite_tree() {
  local from="$1"
  local to="$2"
  local f
  [[ -n "${from}" && "${from}" != "${to}" ]] || return 0
  while IFS= read -r -d '' f; do
    file -b "${f}" 2>/dev/null | grep -qE 'text|ASCII|UTF-8|empty' || continue
    LC_ALL=C sed_inplace "s|${from}|${to}|g" "${f}"
  done < <(find "${STAGE}/etc" -type f -print0)
}

rewrite_tree "${OLD_PREFIX}" "${NEW_PREFIX}"

# Extra prefixes referenced in etc/ (avoid sourcing bashrc; it may exit non-zero).
while IFS= read -r from_path; do
  rewrite_tree "${from_path}" "${NEW_PREFIX}"
done < <(grep -rhoE '/build/openfoam[^"'\''[:space:];]*' "${STAGE}/etc" 2>/dev/null \
  | grep -v "^${NEW_PREFIX}" \
  | sort -u)

echo "[rewrite_openfoam_paths] ${OLD_PREFIX} -> ${NEW_PREFIX} under ${STAGE}/etc"
