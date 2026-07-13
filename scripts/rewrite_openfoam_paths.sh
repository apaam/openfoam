#!/usr/bin/env bash
# Rewrite OpenFOAM etc/ paths for a new install prefix (pack / docker image / CLI).
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

# Extra absolute prefixes still pointing at the old install leaf (any BUILD_ROOT).
old_leaf="$(basename "${OLD_PREFIX}")"
while IFS= read -r from_path; do
  [[ -n "${from_path}" ]] || continue
  rewrite_tree "${from_path}" "${NEW_PREFIX}"
done < <(grep -rhoE "/[^\"'[:space:];]*/${old_leaf}[^\"'[:space:];]*" "${STAGE}/etc" 2>/dev/null \
  | grep -v "^${NEW_PREFIX}" \
  | sort -u || true)

echo "[rewrite_openfoam_paths] ${OLD_PREFIX} -> ${NEW_PREFIX} under ${STAGE}/etc"
