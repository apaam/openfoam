#!/usr/bin/env bash
# Check host build dependencies without installing.
# Exit 0 if present; exit 1 and list gaps otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing=0

case "$(uname -s)" in
Darwin)
  if ! command -v brew >/dev/null 2>&1; then
    echo "[check-deps] brew not found; install Homebrew first" >&2
    exit 1
  fi
  echo "[check-deps] brew bundle check (${ROOT}/Brewfile)"
  if ! brew bundle check --file="${ROOT}/Brewfile"; then
    echo "[check-deps] Missing Homebrew packages. Fix with: make install-deps" >&2
    exit 1
  fi
  ;;
Linux)
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[check-deps] Unsupported Linux: need apt-get (Ubuntu/Debian)" >&2
    exit 1
  fi
  pkgs_file="${ROOT}/scripts/linux_build_packages.txt"
  mapfile -t pkgs < <(grep -v '^#' "${pkgs_file}" | grep -v '^[[:space:]]*$')
  echo "[check-deps] apt packages (${#pkgs[@]} from linux_build_packages.txt)"
  for pkg in "${pkgs[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q 'install ok installed'; then
      echo "[check-deps] missing apt: ${pkg}" >&2
      missing=1
    fi
  done
  echo "[check-deps] pip: setuptools wheel mpi4py"
  for mod in setuptools wheel mpi4py; do
    if ! python3 -c "import ${mod}" >/dev/null 2>&1; then
      echo "[check-deps] missing pip module: ${mod}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    echo "[check-deps] Gaps found. Fix with: make install-deps" >&2
    exit 1
  fi
  ;;
*)
  echo "[check-deps] Unsupported OS: $(uname -s)" >&2
  exit 1
  ;;
esac

echo "[check-deps] OK"
