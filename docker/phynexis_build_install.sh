#!/usr/bin/env bash
# Idempotent apt/pip install for phynexis-build (fresh or extend targets).
set -euo pipefail

PKG_FILE="${PHYNEXIS_BUILD_PACKAGES:-/usr/local/lib/phynexis/build_packages.txt}"

if [[ ! -f "${PKG_FILE}" ]]; then
  echo "[phynexis_build_install] Missing package list: ${PKG_FILE}" >&2
  exit 1
fi

mapfile -t pkgs < <(grep -v '^#' "${PKG_FILE}" | grep -v '^[[:space:]]*$')
if [[ "${#pkgs[@]}" -eq 0 ]]; then
  echo "[phynexis_build_install] Empty package list: ${PKG_FILE}" >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends "${pkgs[@]}"
python3 -m pip install --break-system-packages setuptools wheel mpi4py
rm -rf /var/lib/apt/lists/*

echo "[phynexis_build_install] Done (${#pkgs[@]} apt packages)"
