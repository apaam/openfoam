#!/usr/bin/env bash
# Map system shared-library dependencies of a staged install tree to apt packages.
# Intended to run on phynexis-build after stage_openfoam.sh (ldd + dpkg -S).
set -euo pipefail

PREFIX="${1:?prefix required}"
OUT="${2:-${PREFIX}/../openfoam.runtime-apt.txt}"

if [[ ! -d "${PREFIX}" ]]; then
  echo "[resolve_runtime_apt] Missing prefix: ${PREFIX}" >&2
  exit 1
fi

if ! command -v dpkg >/dev/null 2>&1; then
  echo "[resolve_runtime_apt] dpkg is required" >&2
  exit 1
fi

is_elf() {
  local path="$1"
  file -b "${path}" 2>/dev/null | grep -q 'ELF'
}

is_system_lib() {
  case "$1" in
  /lib/* | /lib64/* | /usr/lib/*) return 0 ;;
  esac
  return 1
}

under_prefix() {
  [[ "$1" == "${PREFIX}"* ]]
}

declare -A packages=()

add_pkg() {
  local pkg="$1"
  [[ -n "${pkg}" ]] || return 0
  case "${pkg}" in
  *-dev | *-dbg | *-dbgsym | *-doc) return 0 ;;
  esac
  packages["${pkg}"]=1
}

map_lib_to_packages() {
  local lib="$1"
  local candidate resolved pkg

  for candidate in "${lib}" "$(readlink -f "${lib}" 2>/dev/null || true)"; do
    [[ -n "${candidate}" && -e "${candidate}" ]] || continue
    while IFS= read -r pkg; do
      add_pkg "${pkg}"
    done < <(
      dpkg -S "${candidate}" 2>/dev/null \
        | grep -Ev '^diversion by ' \
        | grep -E '^[^:]+:([^:]+:)? /' \
        | cut -d: -f1 \
        | sort -u
    )
  done
}

collect_ldd_libs() {
  local bin="$1"
  local line dep

  while IFS= read -r line; do
    dep=""
    if [[ "${line}" =~ =\>\ (.+)\ \(0x ]]; then
      dep="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[[:space:]]*(/[^[:space:]]+) ]]; then
      dep="${BASH_REMATCH[1]}"
    fi
    [[ -n "${dep}" ]] || continue
    printf '%s\n' "${dep}"
  done < <(ldd "${bin}" 2>/dev/null || true)
}

scan_elf() {
  local elf="$1"
  local lib

  is_elf "${elf}" || return 0

  while IFS= read -r lib; do
    [[ -n "${lib}" ]] || continue
    under_prefix "${lib}" && continue
    is_system_lib "${lib}" || continue
    map_lib_to_packages "${lib}"
  done < <(collect_ldd_libs "${elf}")
}

while IFS= read -r -d '' path; do
  scan_elf "${path}"
done < <(find "${PREFIX}" -type f \( -perm -111 -o -name 'lib*.so' -o -name 'lib*.so.*' -o -name '*.so' \) -print0)

# mpirun is not linked by OpenFOAM binaries but required for parallel runs.
for pkg in "${!packages[@]}"; do
  case "${pkg}" in
  libopenmpi* | openmpi-*)
    add_pkg openmpi-bin
    break
    ;;
  esac
done

mkdir -p "$(dirname "${OUT}")"
if ((${#packages[@]} == 0)); then
  echo "[resolve_runtime_apt] No apt packages resolved under ${PREFIX}" >&2
  exit 1
fi

mapfile -t sorted < <(printf '%s\n' "${!packages[@]}" | sort -u)
printf '%s\n' "${sorted[@]}" > "${OUT}"
echo "[resolve_runtime_apt] Wrote ${#sorted[@]} package(s) -> ${OUT}"
