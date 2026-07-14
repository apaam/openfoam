#!/usr/bin/env bash
# Install host build dependencies: Brewfile (macOS) or apt (Ubuntu/Debian).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_apt() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

case "$(uname -s)" in
Darwin)
  echo "[deps] brew bundle (${ROOT}/Brewfile)"
  brew bundle -f --file="${ROOT}/Brewfile"
  ;;
Linux)
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[deps] Unsupported Linux: need apt-get (Ubuntu/Debian)" >&2
    exit 1
  fi
  pkgs_file="${ROOT}/scripts/linux_build_packages.txt"
  mapfile -t pkgs < <(grep -v '^#' "${pkgs_file}" | grep -v '^[[:space:]]*$')
  echo "[deps] apt install (${#pkgs[@]} packages from linux_build_packages.txt)"
  run_apt apt-get update
  run_apt apt-get install -y "${pkgs[@]}"
  echo "[deps] pip: setuptools wheel mpi4py"
  python3 -m pip install --break-system-packages setuptools wheel mpi4py
  ;;
*)
  echo "[deps] Unsupported OS: $(uname -s)" >&2
  exit 1
  ;;
esac

echo "[deps] Done"
