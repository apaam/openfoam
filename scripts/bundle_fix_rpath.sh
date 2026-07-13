#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/platform_paths.sh
source "${SCRIPT_DIR}/platform_paths.sh"

# Usage: fix_rpath.sh <binary> [runtime_dir] [install_path] [search_paths]
# search_paths: colon-separated directories (used on macOS for third-party lookup)

binary="${1:-}"
runtime_dir="${2:-}"
user_install_path="${3:-}"
search_paths="${4:-${FIX_RPATH_SEARCH_PATHS:-}}"

if [[ -z "${binary}" ]] || [[ ! -f "${binary}" ]]; then
  echo "Error: binary not found. Usage: $0 <binary> [runtime_dir] [install_path] [search_paths]" >&2
  exit 1
fi

root_dir="$(dirname "$(dirname "$binary")")"
runtime_dir="${runtime_dir:-${root_dir}/lib}"
search_paths="${search_paths:-${runtime_dir}}"
mkdir -p "${runtime_dir}"

platform="$(uname -s)"
echo "-- Processing ${binary} ..."
echo "-- Platform: ${platform}"
echo "-- Runtime directory: ${runtime_dir}"

parse_otool_dep() {
  local line="$1"
  local dep="${line%% *}"
  dep="${dep%:}"
  dep="${dep#"${dep%%[![:space:]]*}"}"
  dep="${dep%"${dep##*[![:space:]]}"}"
  printf '%s' "${dep}"
}

is_ignored_system_dep() {
  local dep="$1"
  case "${dep}" in
  /usr/lib/* | /System/Library/* | /Library/Developer/*) return 0 ;;
  esac
  if [[ "${dep}" == *Python.framework* ]]; then
    return 0
  fi
  return 1
}

is_project_lib_path() {
  local path="$1"
  [[ -n "${FOAM_LIBBIN:-}" && "${path}" == "${FOAM_LIBBIN}"/* ]] && return 0
  if [[ -n "${WM_PROJECT_DIR:-}" && "${path}" == "${WM_PROJECT_DIR}/platforms/"* ]]; then
    [[ "${path}" == */lib/* || "${path}" == */lib ]] && return 0
  fi
  # staged tree: .../platforms/<plat>/lib/...
  [[ "${path}" == */platforms/*/lib/* ]] && return 0
  return 1
}

codesign_darwin() {
  local path="$1"
  [[ -f "${path}" ]] || return 0
  if command -v codesign >/dev/null; then
    codesign -s - --force "${path}" >/dev/null 2>&1 || true
  fi
}

collect_rpath_search_dirs() {
  local dirs=()
  local dir rpath

  IFS=':' read -ra paths <<< "${search_paths}"
  dirs+=("${paths[@]}")
  dirs+=("${runtime_dir}")

  if [[ -n "${FOAM_LIBBIN:-}" && -d "${FOAM_LIBBIN}" ]]; then
    dirs+=("${FOAM_LIBBIN}")
    for sub in "${FOAM_LIBBIN}"/*; do
      [[ -d "${sub}" ]] && dirs+=("${sub}")
    done
  fi
  if [[ -n "${WM_PROJECT_DIR:-}" ]]; then
    for dir in "${WM_PROJECT_DIR}"/platforms/*/lib; do
      [[ -d "${dir}" ]] && dirs+=("${dir}")
    done
  fi
  while IFS= read -r dir; do
    [[ -n "${dir}" ]] && dirs+=("${dir}")
  done < <(platform_paths_brew_lib_dirs)

  while IFS= read -r rpath; do
    [[ -n "${rpath}" ]] && dirs+=("${rpath}")
  done < <(
    otool -l "${binary}" 2>/dev/null |
      awk '/cmd LC_RPATH/{getline; sub(/^[[:space:]]+path /,""); sub(/ \(offset.*/,""); print}'
  )

  printf '%s\n' "${dirs[@]}" | awk 'NF && !seen[$0]++'
}

has_rpath_darwin() {
  local marker="$1"
  otool -l "${binary}" 2>/dev/null |
    awk '/cmd LC_RPATH/{getline; sub(/^[[:space:]]+path /,""); sub(/ \(offset.*/,""); print}' |
    grep -Fxq "${marker}"
}

ensure_rpath_darwin() {
  local marker="$1"
  if has_rpath_darwin "${marker}"; then
    echo "-- RPATH already contains ${marker}"
    return 0
  fi
  if install_name_tool -add_rpath "${marker}" "${binary}" 2>/dev/null; then
    echo "-- Added RPATH ${marker}"
    return 0
  fi
  echo "WARNING: could not add RPATH ${marker} (headerpad); relying on DYLD_LIBRARY_PATH" >&2
  return 0
}

# Copy a third-party dylib into runtime_dir and rewrite its own absolute deps.
bundle_third_party_dylib_darwin() {
  local src="$1"
  local name dest dep dep_name
  name="$(basename "${src}")"
  dest="${runtime_dir}/${name}"
  _bundled_seen="${_bundled_seen:-}"

  if [[ ":${_bundled_seen}:" == *":${name}:"* ]]; then
    return 0
  fi
  _bundled_seen="${_bundled_seen}:${name}"

  if [[ ! -f "${dest}" ]]; then
    cp -f "${src}" "${dest}"
    chmod u+w "${dest}" 2>/dev/null || true
    echo "-- Copied ${src} -> ${dest}"
  fi

  install_name_tool -id "@rpath/${name}" "${dest}" 2>/dev/null || true

  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    if is_ignored_system_dep "${dep}"; then
      continue
    fi
    case "${dep}" in
    @rpath/* | @executable_path/* | @loader_path/*) continue ;;
    /*)
      if is_project_lib_path "${dep}"; then
        continue
      fi
      dep_name="$(basename "${dep}")"
      if [[ -f "${dep}" ]]; then
        bundle_third_party_dylib_darwin "${dep}"
      elif [[ ! -f "${runtime_dir}/${dep_name}" ]]; then
        while IFS= read -r dir; do
          if [[ -n "${dir}" && -f "${dir}/${dep_name}" ]]; then
            bundle_third_party_dylib_darwin "${dir}/${dep_name}"
            break
          fi
        done < <(collect_rpath_search_dirs)
      fi
      if [[ -f "${runtime_dir}/${dep_name}" ]]; then
        install_name_tool -change "${dep}" "@rpath/${dep_name}" "${dest}" 2>/dev/null || true
      fi
      ;;
    esac
  done < <(otool -L "${dest}" 2>/dev/null | tail -n +2)

  codesign_darwin "${dest}"
}

# Rewrite absolute third-party deps on the target; leave OpenFOAM @rpath alone.
rewrite_third_party_deps_darwin() {
  local dep name changed=false

  if ! command -v install_name_tool >/dev/null; then
    return 0
  fi

  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    if is_ignored_system_dep "${dep}"; then
      continue
    fi
    case "${dep}" in
    @rpath/* | @executable_path/* | @loader_path/*) continue ;;
    /*)
      if is_project_lib_path "${dep}"; then
        continue
      fi
      name="$(basename "${dep}")"
      if [[ -f "${dep}" ]]; then
        bundle_third_party_dylib_darwin "${dep}"
      elif [[ ! -f "${runtime_dir}/${name}" ]]; then
        while IFS= read -r dir; do
          if [[ -n "${dir}" && -f "${dir}/${name}" ]]; then
            bundle_third_party_dylib_darwin "${dir}/${name}"
            break
          fi
        done < <(collect_rpath_search_dirs)
      fi
      if [[ -f "${runtime_dir}/${name}" ]]; then
        # @rpath/name is shorter than Homebrew absolute paths -> fits headerpad.
        if install_name_tool -change "${dep}" "@rpath/${name}" "${binary}"; then
          echo "-- Rewrote ${dep} -> @rpath/${name}"
          changed=true
        else
          echo "Error: install_name_tool failed rewriting ${dep}" >&2
          return 1
        fi
      else
        echo "Error: missing third-party library for ${dep}" >&2
        return 1
      fi
      ;;
    esac
  done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)

  if [[ "${changed}" == true ]]; then
    ensure_rpath_darwin "${path_marker}"
  fi
}

# True when only system / @rpath / already-bundled refs remain.
darwin_deps_ok() {
  local dep name
  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    if is_ignored_system_dep "${dep}"; then
      continue
    fi
    case "${dep}" in
    @rpath/* | @executable_path/* | @loader_path/*) continue ;;
    /*)
      if is_project_lib_path "${dep}"; then
        continue
      fi
      return 1
      ;;
    *)
      return 1
      ;;
    esac
  done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)
  return 0
}

copy_linux_dep() {
  local src="$1"
  local name dest
  name="$(basename "${src}")"
  dest="${runtime_dir}/${name}"
  if [[ ! -f "${dest}" ]]; then
    cp -fL "${src}" "${dest}"
    chmod u+w "${dest}" 2>/dev/null || true
    echo "-- Copied ${src} -> ${dest}"
  fi
}

is_openmpi_runtime_soname_linux() {
  local name="$1"
  case "${name}" in
  libmpi.so* | libmpi_*.so* | libopen-*.so* | liboshmem.so* | \
  libmca_*.so* | libmca_common_*.so* | libompitrace.so* | \
  libpmix.so* | libhwloc.so* | libevent*.so* | libfabric.so* | \
  libibverbs.so* | libpsm2.so* | libpsm_infinipath.so* | libucx.so* | \
  libmunge.so* | libnl-3.so* | libnl-route-3.so*)
    return 0
    ;;
  esac
  return 1
}

is_ignored_system_dep_linux() {
  local dep="$1"
  local name
  # Ubuntu/Debian usrmerge: ldd often reports /lib/<triplet>/libmpi.so.*
  # (same inode as /usr/lib/...). OpenMPI must still be bundled for portable
  # dist-native / Docker images that do not install system MPI.
  case "${dep}" in
  /lib/* | /lib32/* | /lib64/* | /usr/lib/* | /usr/lib32/* | /usr/lib64/*)
    name="$(basename "${dep}")"
    if is_openmpi_runtime_soname_linux "${name}"; then
      return 1
    fi
    return 0
    ;;
  esac
  return 1
}

parse_ldd_resolved() {
  # Prints absolute path, or NOTFOUND:<soname>, or empty for vdso/loader lines.
  local line="$1"
  local soname path
  if [[ "${line}" == *"not found"* ]]; then
    soname="$(echo "${line}" | awk '{print $1}')"
    printf 'NOTFOUND:%s' "${soname}"
    return 0
  fi
  path="$(echo "${line}" | awk '/=>/ {print $3}')"
  if [[ -n "${path}" && "${path}" == /* ]]; then
    printf '%s' "${path}"
    return 0
  fi
  # e.g. /lib64/ld-linux-x86-64.so.2 => /lib64/ld-linux-x86-64.so.2
  path="$(echo "${line}" | awk '{print $1}')"
  if [[ "${path}" == /* ]]; then
    printf '%s' "${path}"
  fi
}

ensure_linux_rpath() {
  local target="$1"
  local marker="$2"
  local current
  current="$(patchelf --print-rpath "${target}" 2>/dev/null || true)"
  if [[ ":${current}:" == *":${marker}:"* ]]; then
    echo "-- RPATH already contains ${marker} (${target##*/})"
    return 0
  fi
  if [[ -n "${current}" ]]; then
    patchelf --set-rpath "${marker}:${current}" "${target}"
  else
    patchelf --set-rpath "${marker}" "${target}"
  fi
  echo "-- Set RPATH ${marker} on ${target##*/}"
}

# Recursively copy a third-party .so and point its RPATH at $ORIGIN (siblings).
bundle_third_party_so_linux() {
  local src="$1"
  local name dest dep dep_path
  name="$(basename "${src}")"
  dest="${runtime_dir}/${name}"
  _bundled_seen="${_bundled_seen:-}"

  if [[ ":${_bundled_seen}:" == *":${name}:"* ]]; then
    return 0
  fi
  _bundled_seen="${_bundled_seen}:${name}"

  if [[ ! -f "${src}" ]]; then
    echo "Error: missing third-party library ${src}" >&2
    return 1
  fi

  copy_linux_dep "${src}"
  # Bundled libs resolve each other via $ORIGIN.
  ensure_linux_rpath "${dest}" '$ORIGIN'

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    dep_path="$(parse_ldd_resolved "${line}")"
    [[ -n "${dep_path}" ]] || continue
    if [[ "${dep_path}" == NOTFOUND:* ]]; then
      echo "Error: unresolved dependency ${dep_path#NOTFOUND:} while bundling ${name}" >&2
      return 1
    fi
    if is_ignored_system_dep_linux "${dep_path}"; then
      continue
    fi
    if is_project_lib_path "${dep_path}"; then
      continue
    fi
    bundle_third_party_so_linux "${dep_path}"
  done < <(ldd "${dest}" 2>/dev/null || true)
}

rewrite_linux_deps() {
  local dep_path name
  local found_third_party=false

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    dep_path="$(parse_ldd_resolved "${line}")"
    [[ -n "${dep_path}" ]] || continue
    if [[ "${dep_path}" == NOTFOUND:* ]]; then
      echo "Error: unresolved dependency ${dep_path#NOTFOUND:} in ${binary}" >&2
      return 1
    fi
    if is_ignored_system_dep_linux "${dep_path}"; then
      continue
    fi
    if is_project_lib_path "${dep_path}"; then
      continue
    fi
    found_third_party=true
    bundle_third_party_so_linux "${dep_path}"
  done < <(ldd "${binary}" 2>/dev/null || true)

  if [[ "${found_third_party}" == true ]]; then
    ensure_linux_rpath "${binary}" "${path_marker}"
  fi
}

linux_deps_ok() {
  local dep_path name
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    dep_path="$(parse_ldd_resolved "${line}")"
    if [[ "${dep_path}" == NOTFOUND:* ]]; then
      return 1
    fi
    [[ -n "${dep_path}" ]] || continue
    if is_ignored_system_dep_linux "${dep_path}"; then
      continue
    fi
    if is_project_lib_path "${dep_path}"; then
      continue
    fi
    # Build machine ldd still resolves apt/brew paths; require a bundled copy.
    name="$(basename "${dep_path}")"
    if [[ ! -f "${runtime_dir}/${name}" ]]; then
      return 1
    fi
  done < <(ldd "${binary}" 2>/dev/null || true)
  return 0
}

linux_has_third_party() {
  local dep_path
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    dep_path="$(parse_ldd_resolved "${line}")"
    [[ -n "${dep_path}" && "${dep_path}" != NOTFOUND:* ]] || continue
    if is_ignored_system_dep_linux "${dep_path}"; then
      continue
    fi
    if is_project_lib_path "${dep_path}"; then
      continue
    fi
    return 0
  done < <(ldd "${binary}" 2>/dev/null || true)
  return 1
}

should_skip_linux() {
  local rpath="$1"
  if ! linux_has_third_party; then
    return 0
  fi
  if [[ ":${rpath}:" != *":${path_marker}:"* ]]; then
    return 1
  fi
  linux_deps_ok
}

if [[ "${platform}" == "Darwin" ]]; then
  filetype_line="$(otool -hv "${binary}")"
  if echo "${filetype_line}" | grep -q "EXECUTE"; then
    detected_path_marker='@executable_path'
    filetype='EXECUTE'
  elif echo "${filetype_line}" | grep -q "DYLIB"; then
    detected_path_marker='@loader_path'
    filetype='DYLIB'
  else
    detected_path_marker='@loader_path'
    filetype='UNKNOWN'
  fi
  echo "-- Detected filetype: ${filetype} (default path marker: ${detected_path_marker})"

  if [[ -n "${user_install_path}" && "${user_install_path}" != *"${detected_path_marker}"* ]]; then
    echo "WARNING: install_path '${user_install_path}' differs from default '${detected_path_marker}'."
  fi

  path_marker="${user_install_path:-${detected_path_marker}/../lib}"
  echo "-- Using path marker: ${path_marker}"

  # Only rewrite install id for dylibs that live inside the bundled runtime dir.
  if [[ "${binary}" == "${runtime_dir}"/* ]]; then
    base_name="$(basename "${binary}")"
    install_name_tool -id "@rpath/${base_name}" "${binary}" 2>/dev/null || true
  fi

  if darwin_deps_ok; then
    echo "-- No third-party absolute deps; leaving OpenFOAM @rpath intact"
    exit 0
  fi

  rewrite_third_party_deps_darwin

  if ! darwin_deps_ok; then
    echo "Error: unresolved third-party dependencies remain in ${binary}" >&2
    otool -L "${binary}" >&2 || true
    exit 1
  fi

  codesign_darwin "${binary}"
  echo "-- Bundled third-party deps for ${binary}"

elif [[ "${platform}" == "Linux" ]]; then
  detected_path_marker='$ORIGIN'
  if [[ -n "${user_install_path}" && "${user_install_path}" != *"${detected_path_marker}"* ]]; then
    echo "WARNING: install_path '${user_install_path}' differs from default '${detected_path_marker}'."
  fi
  path_marker="${user_install_path:-${detected_path_marker}/../lib}"
  echo "-- Using path marker: ${path_marker}"

  if ! command -v patchelf >/dev/null; then
    echo "Error: patchelf not found" >&2
    exit 1
  fi

  current_rpath="$(patchelf --print-rpath "${binary}" 2>/dev/null || true)"
  if should_skip_linux "${current_rpath}"; then
    echo "-- Already bundled / no third-party deps, skipping ${binary}"
    exit 0
  fi

  rewrite_linux_deps

  if ! linux_deps_ok; then
    echo "Error: unresolved third-party dependencies remain in ${binary}" >&2
    ldd "${binary}" >&2 || true
    exit 1
  fi

  echo "-- Bundled third-party deps for ${binary}"
else
  echo "Error: unsupported platform: ${platform}" >&2
  exit 1
fi

echo "-- Done fixing ${binary}"
