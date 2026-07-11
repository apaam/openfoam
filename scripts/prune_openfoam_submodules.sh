#!/usr/bin/env bash
# Deinit nested modules/plugins submodules inside openfoam-source (core build only).
set -euo pipefail

ROOT="${OPENFOAM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOURCE="${OPENFOAM_SOURCE:-${ROOT}/openfoam-source}"

git -C "${SOURCE}" rev-parse --is-inside-work-tree &>/dev/null || exit 0

while IFS= read -r path; do
  [[ -n "${path}" ]] || continue
  git -C "${SOURCE}" submodule deinit -f -- "${path}" 2>/dev/null || true
  rm -rf "${SOURCE}/${path}"
done < <(
  git -C "${SOURCE}" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '$2 ~ /^(modules|plugins)\// { print $2 }'
)
