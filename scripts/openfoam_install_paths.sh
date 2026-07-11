#!/usr/bin/env bash
# Shared path lists for OpenFOAM install tree packaging.
# build_openfoam.sh copies openfoam-source/ into build/, then Allwmake adds platforms/ and build/.
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
      mkdir -p "${dst}/${item}"
      rsync -a --delete "${src}/${item}/" "${dst}/${item}/"
    else
      rsync -a "${src}/${item}" "${dst}/${item}"
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
      rm -rf "${existing}"
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
