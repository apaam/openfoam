#!/usr/bin/env bash
# Bundle third-party shared libraries into STAGE/lib and fix rpath.
set -euo pipefail

STAGE="${1:?stage prefix required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/platform_paths.sh
source "${ROOT}/scripts/platform_paths.sh"
FIX_RPATH="${ROOT}/scripts/bundle_fix_rpath.sh"
RUNTIME_DIR="${STAGE}/lib"

if [[ ! -f "${STAGE}/etc/bashrc" ]]; then
  echo "[bundle_openfoam_runtime] Missing ${STAGE}/etc/bashrc" >&2
  exit 1
fi

platform="$(uname -s)"
if [[ "${platform}" == "Linux" ]] && ! command -v patchelf >/dev/null; then
  echo "[bundle_openfoam_runtime] patchelf required" >&2
  exit 1
fi

mkdir -p "${RUNTIME_DIR}"
# Migrate away from the former lib/bundled layout.
if [[ -d "${STAGE}/lib/bundled" ]]; then
  echo "[bundle_openfoam_runtime] Removing legacy ${STAGE}/lib/bundled"
  rm -rf "${STAGE}/lib/bundled"
fi

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

  while IFS= read -r dir; do
    [[ -n "${dir}" ]] && paths+=("${dir}")
  done < <(platform_paths_brew_lib_dirs)

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
  case "${path}" in
  *.o | *.a | *.pyc) return 1 ;;
  esac
  case "${platform}" in
  Darwin)
    file -b "${path}" 2>/dev/null | grep -qE 'Mach-O.*(executable|dynamically linked shared library|bundle)'
    ;;
  Linux)
    file -b "${path}" 2>/dev/null | grep -qE 'ELF.*(executable|shared object)'
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
      printf '@loader_path/../../../lib'
    elif [[ "${target}" == */platforms/*/bin/* ]]; then
      printf '@executable_path/../../../lib'
    else
      printf '@executable_path/../lib'
    fi
    ;;
  Linux)
    if [[ "${target}" == */platforms/*/lib/* || "${target}" == */platforms/*/bin/* ]]; then
      printf '$ORIGIN/../../../lib'
    else
      printf '$ORIGIN/../lib'
    fi
    ;;
  esac
}

set +eu
# shellcheck disable=SC1091
source "${STAGE}/etc/bashrc"
export SHELL="$(platform_paths_resolve_bash)"
set -eu

SEARCH_PATHS="$(collect_search_paths)"
export FIX_RPATH_SEARCH_PATHS="${SEARCH_PATHS}"

# shellcheck disable=SC1091
source "${ROOT}/scripts/bundle_openmpi_discover.sh"
openmpi_discover_extras_paths "${STAGE}"

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

if ((failures > 0)); then
  echo "[bundle_openfoam_runtime] Failed for ${failures}/${total} target(s); logs: ${STAGE}/.bundle-log-*.txt" >&2
  exit 1
fi

rm -f "${STAGE}"/.bundle-log-*.txt

if [[ "${platform}" == "Linux" || "${platform}" == "Darwin" ]]; then
  bash "${ROOT}/scripts/bundle_openmpi_extras.sh" "${STAGE}"
fi

date -u +%Y-%m-%dT%H:%M:%SZ > "${RUNTIME_DIR}/.bundle-stamp"
echo "[bundle_openfoam_runtime] Done"
