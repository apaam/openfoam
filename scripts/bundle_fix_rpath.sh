#!/usr/bin/env bash
set -euo pipefail

# Usage: fix_rpath.sh <binary> [runtime_dir] [install_path] [search_paths]
# search_paths: colon-separated directories (used on macOS for dylibbundler -s)

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

collect_rpath_search_dirs() {
  local dirs=()
  local dir rpath

  IFS=':' read -ra paths <<< "${search_paths}"
  dirs+=("${paths[@]}")

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
  if [[ "${platform}" == "Darwin" && -d /opt/homebrew/opt ]]; then
    for dir in /opt/homebrew/opt/*/lib; do
      [[ -d "${dir}" ]] && dirs+=("${dir}")
    done
  fi

  while IFS= read -r rpath; do
    [[ -n "${rpath}" ]] && dirs+=("${rpath}")
  done < <(
    otool -l "${binary}" 2>/dev/null |
      awk '/cmd LC_RPATH/{getline; sub(/^[[:space:]]+path /,""); sub(/ \(offset.*/,""); print}'
  )

  printf '%s\n' "${dirs[@]}" | awk 'NF && !seen[$0]++'
}

fix_dylib_install_name_darwin() {
  local id_name base_name
  base_name="$(basename "${binary}")"
  id_name="$(otool -D "${binary}" 2>/dev/null | tail -1 | xargs)"
  if [[ "${id_name}" == @rpath/* || "${id_name}" == /* ]]; then
    install_name_tool -id "${path_marker}/${base_name}" "${binary}"
    echo "-- Set install name ${path_marker}/${base_name}"
  fi
}

resolve_rpath_deps_darwin() {
  local dep libname resolved changed round=0

  if ! command -v install_name_tool >/dev/null; then
    return 0
  fi

  while ((round < 32)); do
    changed=false
    while IFS= read -r line; do
      dep="$(parse_otool_dep "${line}")"
      [[ "${dep}" == @rpath/* ]] || continue
      libname="${dep#@rpath/}"
      if [[ "${libname}" == "$(basename "${binary}")" ]]; then
        install_name_tool -change "${dep}" "${path_marker}/${libname}" "${binary}"
        echo "-- Resolved self ${dep} -> ${path_marker}/${libname}"
        changed=true
        continue
      fi
      resolved=""
      while IFS= read -r dir; do
        [[ -n "${dir}" && -f "${dir}/${libname}" ]] || continue
        resolved="${dir}/${libname}"
        break
      done < <(collect_rpath_search_dirs)
      if [[ -n "${resolved}" ]]; then
        install_name_tool -change "${dep}" "${resolved}" "${binary}"
        echo "-- Resolved ${dep} -> ${resolved}"
        changed=true
      fi
    done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)

    [[ "${changed}" == true ]] || break
    round=$((round + 1))
  done
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

should_skip_darwin() {
  local dep name needs_bundle=false
  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    if is_ignored_system_dep "${dep}"; then
      continue
    fi
    case "${dep}" in
    @executable_path/../lib/* | @loader_path/../lib/*)
      name="${dep##*/}"
      if [[ "${name}" == "Python" ]]; then
        continue
      fi
      if [[ ! -f "${runtime_dir}/${name}" ]]; then
        needs_bundle=true
      fi
      ;;
    *) needs_bundle=true ;;
    esac
  done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)
  [[ "${needs_bundle}" == false ]]
}

rewrite_dylib_paths_darwin() {
  local dep name target

  if ! command -v install_name_tool >/dev/null; then
    return 0
  fi

  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    case "${dep}" in
    /usr/lib/* | /System/Library/* | /Library/Developer/*) continue ;;
    @loader_path/../lib/* | @executable_path/../lib/*) continue ;;
    /*)
      name="${dep##*/}"
      if [[ ! -f "${runtime_dir}/${name}" ]]; then
        while IFS= read -r dir; do
          if [[ -n "${dir}" && -f "${dir}/${name}" ]]; then
            cp -f "${dir}/${name}" "${runtime_dir}/${name}"
            echo "-- Copied ${dir}/${name} -> ${runtime_dir}/${name}"
            break
          fi
        done < <(collect_rpath_search_dirs)
      fi
      target="${path_marker}/${name}"
      if [[ -f "${runtime_dir}/${name}" ]]; then
        install_name_tool -change "${dep}" "${target}" "${binary}"
        echo "-- Rewrote ${dep} -> ${target}"
      fi
      ;;
    esac
  done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)
}

needs_dylibbundler_darwin() {
  local dep
  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    if is_ignored_system_dep "${dep}"; then
      continue
    fi
    case "${dep}" in
    @executable_path/../lib/* | @loader_path/../lib/*) continue ;;
    @rpath/*)
      libname="${dep#@rpath/}"
      if [[ "${libname}" == "$(basename "${binary}")" ]]; then
        continue
      fi
      return 0
      ;;
    /*) return 0 ;;
    esac
  done < <(otool -L "${binary}" 2>/dev/null | tail -n +2)
  return 1
}

should_skip_linux() {
  local rpath dep
  rpath="$(patchelf --print-rpath "${binary}" 2>/dev/null || true)"
  path_marker="${1}"
  if [[ ":${rpath}:" != *":${path_marker}:"* ]]; then
    return 1
  fi
  while IFS= read -r line; do
    dep="$(parse_otool_dep "${line}")"
    case "${dep}" in
    linux-vdso.so.* | ld-linux-*.so.* | /lib/* | /lib64/* | /usr/lib/*) continue ;;
    ${runtime_dir}/*) continue ;;
    *) return 1 ;;
    esac
  done < <(ldd "${binary}" 2>/dev/null | tail -n +2 || true)
  return 0
}

run_dylibbundler() {
  local path_marker="$1"
  local search_path output rc last_output="" last_rc=1

  if ! command -v dylibbundler >/dev/null; then
    echo "Error: dylibbundler not found (brew install dylibbundler)" >&2
    return 1
  fi

  IFS=':' read -ra paths <<< "${search_paths}"
  if ((${#paths[@]} == 0)); then
    paths=("${runtime_dir}")
  fi

  for search_path in "${paths[@]}"; do
    [[ -n "${search_path}" && -d "${search_path}" ]] || continue
    echo "-- dylibbundler search path: ${search_path}"
    set +e
    output="$(
      dylibbundler -b -of -cd \
        -x "${binary}" \
        -d "${runtime_dir}" \
        -s "${search_path}" \
        -p "${path_marker}" 2>&1
    )"
    rc=$?
    set -e
    if [[ -n "${output}" ]]; then
      echo "${output}"
    fi
    last_output="${output}"
    last_rc=${rc}
    if [[ ${rc} -eq 0 ]]; then
      if ! echo "${output}" | grep -qE 'WARNING'; then
        return 0
      fi
      if ! echo "${output}" | grep -E 'WARNING' |
        grep -vE "Cannot resolve path '@executable_path|Cannot resolve path '@loader_path" |
        grep -q .; then
        return 0
      fi
    fi
  done

  if [[ ${last_rc} -ne 0 ]]; then
    return "${last_rc}"
  fi
  if echo "${last_output}" | grep -qE 'WARNING'; then
    return 1
  fi
  return 0
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

  if [[ "${filetype}" == "DYLIB" || "${binary}" == *.so ]]; then
    fix_dylib_install_name_darwin
  fi

  resolve_rpath_deps_darwin || true
  rewrite_dylib_paths_darwin

  if should_skip_darwin; then
    echo "-- Already bundled, skipping ${binary}"
    exit 0
  fi

  if needs_dylibbundler_darwin; then
    echo "Error: unresolved dependencies remain in ${binary} (set FOAM_LIBBIN for OpenFOAM targets)" >&2
    otool -L "${binary}" >&2 || true
    exit 1
  fi

  echo "-- Rewrote paths with install_name_tool"

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

  if should_skip_linux "${path_marker}"; then
    echo "-- Already bundled, skipping ${binary}"
    exit 0
  fi

  current_rpath="$(patchelf --print-rpath "${binary}" 2>/dev/null || true)"
  if [[ ":${current_rpath}:" != *":${path_marker}:"* ]]; then
    patchelf --add-rpath "${path_marker}" "${binary}"
  else
    echo "-- RPATH already contains ${path_marker}"
  fi
else
  echo "Error: unsupported platform: ${platform}" >&2
  exit 1
fi

echo "-- Done fixing ${binary}"
