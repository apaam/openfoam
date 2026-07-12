#!/usr/bin/env bash
# Shared path lists for OpenFOAM install tree packaging.
# build_openfoam.sh copies openfoam-source/ into OPENFOAM_BUILD (build/openfoam/),
# then Allwmake adds platforms/ and build/ (wmake objects) there.
# Packaging outputs live under build/stage/, build/wheel/, etc.
# shellcheck shell=bash

# Optional OpenFOAM components (not built by default); omit from source sync.
OPENFOAM_SOURCE_SYNC_EXCLUDES=(
  --exclude=modules/
  --exclude=plugins/
)

# Whitelist top-level paths under WM_PROJECT_DIR for packaging and cache sync.
OPENFOAM_INSTALL_INCLUDES=(
  etc
  bin
  platforms
  src
  applications
  wmake
  tutorials
  META-INFO
)

# macOS Finder may drop .DS_Store while large trees are being removed, leaving
# ENOTEMPTY ("Directory not empty") from rm/rmtree. Move aside first when needed.
openfoam_safe_rm() {
  local target="$1"
  [[ -e "${target}" ]] || return 0

  if [[ "$(uname -s)" == "Darwin" ]]; then
    export COPYFILE_DISABLE=1
  fi

  find "${target}" -name .DS_Store -delete 2>/dev/null || true
  chmod -R u+w "${target}" 2>/dev/null || true
  if rm -rf "${target}" 2>/dev/null; then
    return 0
  fi

  local trash parent base
  parent="$(dirname "${target}")"
  base="$(basename "${target}")"
  trash="$(mktemp -d "${TMPDIR:-/tmp}/openfoam-rm.XXXXXX")"
  if mv "${target}" "${trash}/${base}" 2>/dev/null; then
    rm -rf "${trash}" &
    return 0
  fi

  find "${target}" -name .DS_Store -delete 2>/dev/null || true
  rm -rf "${target}"
}

# Sync only whitelisted paths from src/ to dst/ (packaging, cache).
# Optional third argument: space-separated extra top-level paths (STAGE_EXTRA_INCLUDES).
openfoam_rsync_install_tree() {
  local src="${1:?source dir}"
  local dst="${2:?dest dir}"
  local extra="${3:-}"
  local -a includes=()
  local item name existing found

  includes=("${OPENFOAM_INSTALL_INCLUDES[@]}")
  for item in ${extra}; do
    includes+=("${item}")
  done

  mkdir -p "${dst}"

  for item in "${includes[@]}"; do
    if [[ ! -e "${src}/${item}" ]]; then
      echo "[openfoam_rsync_install_tree] Missing ${src}/${item}" >&2
      return 1
    fi
    if [[ -d "${src}/${item}" ]]; then
      openfoam_safe_rm "${dst}/${item}"
      mkdir -p "${dst}"
      (cd "${src}" && tar -cf - "${item}") | (cd "${dst}" && tar -xf -)
    else
      cp -a "${src}/${item}" "${dst}/${item}"
    fi
  done

  shopt -s nullglob
  for existing in "${dst}"/*; do
    name="$(basename "${existing}")"
    case "${name}" in
    .stage-stamp | .dist-stamp | .pack-stamp | .pack-source-prefix | lib | share) continue ;;
    esac
    found=false
    for item in "${includes[@]}"; do
      if [[ "${name}" == "${item}" ]]; then
        found=true
        break
      fi
    done
    if [[ "${found}" == false ]]; then
      openfoam_safe_rm "${existing}"
    fi
  done
  shopt -u nullglob
}

# Return required install paths (default includes + optional extras).
openfoam_install_paths() {
  local extra="${1:-}"
  local -a paths=("${OPENFOAM_INSTALL_INCLUDES[@]}")
  local item
  for item in ${extra}; do
    paths+=("${item}")
  done
  printf '%s\n' "${paths[@]}"
}

openfoam_pack_stamp_matches() {
  local stamp="${1:?pack stamp}"
  local bundle="${2:?bundle mode}"
  [[ -f "${stamp}" ]] || return 1
  grep -q "^bundle=${bundle}$" "${stamp}" 2>/dev/null
}
