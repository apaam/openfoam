#!/usr/bin/env bash
# Bundle third-party shared libraries into STAGE/lib/bundled and fix rpath.
set -euo pipefail

STAGE="${1:?stage prefix required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX_RPATH="${ROOT}/scripts/bundle_fix_rpath.sh"
RUNTIME_DIR="${STAGE}/lib/bundled"

if [[ ! -f "${STAGE}/etc/bashrc" ]]; then
  echo "[bundle_openfoam_runtime] Missing ${STAGE}/etc/bashrc" >&2
  exit 1
fi

platform="$(uname -s)"
if [[ "${platform}" == "Darwin" ]] && ! command -v dylibbundler >/dev/null; then
  echo "[bundle_openfoam_runtime] dylibbundler required (brew install dylibbundler)" >&2
  exit 1
fi
if [[ "${platform}" == "Linux" ]] && ! command -v patchelf >/dev/null; then
  echo "[bundle_openfoam_runtime] patchelf required" >&2
  exit 1
fi

mkdir -p "${RUNTIME_DIR}"

collect_search_paths() {
  local paths=("${RUNTIME_DIR}")
  local dir joined=""

  if [[ -n "${FOAM_LIBBIN:-}" && -d "${FOAM_LIBBIN}" ]]; then
    paths+=("${FOAM_LIBBIN}")
    for dir in "${FOAM_LIBBIN}"/*; do
      [[ -d "${dir}" ]] && paths+=("${dir}")
    done
  fi
  for dir in "${STAGE}"/platforms/*/lib; do
    [[ -d "${dir}" ]] && paths+=("${dir}")
  done
  if [[ -d "${STAGE}/lib" ]]; then
    paths+=("${STAGE}/lib")
  fi

  if [[ "${platform}" == "Darwin" && -d /opt/homebrew/lib ]]; then
    paths+=("/opt/homebrew/lib")
    for dir in /opt/homebrew/opt/*/lib; do
      [[ -d "${dir}" ]] && paths+=("${dir}")
    done
  elif [[ -d /usr/local/lib ]]; then
    paths+=("/usr/local/lib")
  fi

  if [[ -n "${DYLD_LIBRARY_PATH:-}" ]]; then
    IFS=':' read -ra extra <<< "${DYLD_LIBRARY_PATH}"
    paths+=("${extra[@]}")
  fi
  if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    IFS=':' read -ra extra <<< "${LD_LIBRARY_PATH}"
    paths+=("${extra[@]}")
  fi

  joined="${paths[0]}"
  local i
  for ((i = 1; i < ${#paths[@]}; i++)); do
    joined="${joined}:${paths[i]}"
  done
  printf '%s' "${joined}"
}

is_bundle_target() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  case "${platform}" in
  Darwin)
    file -b "${path}" 2>/dev/null | grep -qE 'Mach-O (executable|64-bit|dylib|bundle)'
    ;;
  Linux)
    file -b "${path}" 2>/dev/null | grep -q 'ELF'
    ;;
  *)
    return 1
    ;;
  esac
}

path_marker_for() {
  local target="$1"
  case "${platform}" in
  Darwin)
    if [[ "${target}" == */platforms/*/lib/* ]]; then
      printf '@loader_path/../../../lib/bundled'
    else
      printf '@executable_path/../lib/bundled'
    fi
    ;;
  Linux)
    if [[ "${target}" == */platforms/*/lib/* ]]; then
      printf '$ORIGIN/../../../lib/bundled'
    else
      printf '$ORIGIN/../lib/bundled'
    fi
    ;;
  esac
}

set +eu
export SHELL=/bin/bash
# shellcheck disable=SC1091
source "${STAGE}/etc/bashrc"
set -eu

SEARCH_PATHS="$(collect_search_paths)"
export FIX_RPATH_SEARCH_PATHS="${SEARCH_PATHS}"

targets=()
while IFS= read -r path; do
  [[ -n "${path}" ]] || continue
  is_bundle_target "${path}" && targets+=("${path}")
done < <(
  find "${STAGE}/bin" "${STAGE}/platforms" -type f 2>/dev/null \
    | sort -u
)

if ((${#targets[@]} == 0)); then
  echo "[bundle_openfoam_runtime] No bundle targets under ${STAGE}" >&2
  exit 1
fi

echo "[bundle_openfoam_runtime] Bundling ${#targets[@]} target(s) -> ${RUNTIME_DIR}/"
failures=0
count=0
total=${#targets[@]}
for target in "${targets[@]}"; do
  count=$((count + 1))
  marker="$(path_marker_for "${target}")"
  name="$(basename "${target}")"
  echo "[bundle_openfoam_runtime] [${count}/${total}] ${name}"
  if ! FIX_RPATH_SEARCH_PATHS="${SEARCH_PATHS}" \
    "${FIX_RPATH}" "${target}" "${RUNTIME_DIR}" "${marker}" "${SEARCH_PATHS}" \
    >"${STAGE}/.bundle-log-${count}.txt" 2>&1; then
    echo "[bundle_openfoam_runtime] Failed: ${target} (see ${STAGE}/.bundle-log-${count}.txt)" >&2
    failures=$((failures + 1))
  fi
done

rm -f "${STAGE}"/.bundle-log-*.txt
if ((failures > 0)); then
  echo "[bundle_openfoam_runtime] Failed for ${failures}/${total} target(s)" >&2
  exit 1
fi

date -u +%Y-%m-%dT%H:%M:%SZ > "${RUNTIME_DIR}/.bundle-stamp"
echo "[bundle_openfoam_runtime] Done"
