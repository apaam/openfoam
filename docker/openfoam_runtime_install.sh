#!/usr/bin/env bash
# Install apt packages resolved by resolve_runtime_apt.sh.
set -euo pipefail

PKG_FILE="${OPENFOAM_RUNTIME_PACKAGES:?OPENFOAM_RUNTIME_PACKAGES required}"

if [[ ! -f "${PKG_FILE}" ]]; then
  echo "[openfoam_runtime_install] Missing package list: ${PKG_FILE}" >&2
  exit 1
fi

mapfile -t pkgs < <(grep -v '^#' "${PKG_FILE}" | grep -v '^[[:space:]]*$')
if [[ "${#pkgs[@]}" -eq 0 ]]; then
  echo "[openfoam_runtime_install] Empty package list: ${PKG_FILE}" >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends ca-certificates "${pkgs[@]}"
rm -rf /var/lib/apt/lists/*

echo "[openfoam_runtime_install] Done (${#pkgs[@]} resolved + ca-certificates)"
