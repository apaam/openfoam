#!/usr/bin/env bash
# Shared path lists for OpenFOAM install tree packaging.
# build_openfoam.sh copies openfoam-source/ into OPENFOAM_BUILD (see docs/make-config-default.mk).
# then Allwmake adds platforms/ and build/ (wmake objects) there.
# Packaging outputs live under build/stage/, build/wheel/, etc.
# shellcheck shell=bash

# Optional OpenFOAM components (not built by default); omit from source sync.
OPENFOAM_SOURCE_SYNC_EXCLUDES=(
  --exclude=modules/
  --exclude=plugins/
)

# Whitelist top-level paths under WM_PROJECT_DIR for packaging sync.
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

# Runtime-only paths (used when splitting install trees).
OPENFOAM_RUNTIME_INCLUDES=(
  etc
  bin
  platforms
  tutorials
  META-INFO
)

# Compile tree paths (optional split packaging).
OPENFOAM_DEV_INCLUDES=(
  src
  applications
  wmake
)

# macOS Finder may drop .DS_Store while large trees are being removed, leaving
# ENOTEMPTY ("Directory not empty") from rm/rmtree. Move aside first when needed.
openfoam_dir_case_sensitive() {
  local dir="$1" probe
  [[ -d "${dir}" ]] || return 0
  probe="$(mktemp -d "${dir}/.case-probe.XXXXXX")"
  rm -f "${probe}/probe_a" "${probe}/PROBE_A"
  touch "${probe}/probe_a"
  if [[ -e "${probe}/PROBE_A" ]]; then
    openfoam_safe_rm "${probe}"
    return 1
  fi
  openfoam_safe_rm "${probe}"
  return 0
}

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

# Sync only whitelisted paths from src/ to dst/ (packaging).
# Optional third argument: space-separated extra top-level paths (STAGE_EXTRA_INCLUDES).
# Optional fourth argument: "runtime" | "dev" | "full" (default full).
openfoam_rsync_install_tree() {
  local src="${1:?source dir}"
  local dst="${2:?dest dir}"
  local extra="${3:-}"
  local mode="${4:-full}"
  local -a includes=()
  local item name existing found

  if [[ "${mode}" == runtime ]]; then
    includes=("${OPENFOAM_RUNTIME_INCLUDES[@]}")
  elif [[ "${mode}" == dev ]]; then
    includes=("${OPENFOAM_DEV_INCLUDES[@]}")
  else
    includes=("${OPENFOAM_INSTALL_INCLUDES[@]}")
  fi
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
      # lnInclude symlinks are required for wmake; keep them in prefix tar.
      (cd "${src}" && tar -cf - \
        --exclude='.DS_Store' \
        --exclude='*/.DS_Store' \
        "${item}") | (cd "${dst}" && tar -xf -)
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

# Pack install tree into openfoam-prefix.tar.gz from staged prefix (case-sensitive volume).
openfoam_pack_prefix_tar() {
  local src="${1:?source stage}"
  local archive="${2:?output .tar.gz}"
  local pack_parent

  pack_parent="$(dirname "${src}")"
  if [[ "$(uname -s)" == "Darwin" ]] && [[ -d "${pack_parent}" ]] \
    && ! openfoam_dir_case_sensitive "${pack_parent}"; then
    echo "[openfoam_pack_prefix_tar] Pack parent must be case-sensitive: ${pack_parent}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${archive}")"
  tar -czf "${archive}" -C "${src}" \
    --exclude='.DS_Store' \
    --exclude='*/.DS_Store' \
    --exclude='.stage-stamp' \
    --exclude='.pack-stamp' \
    --exclude='.dist-stamp' \
    .
}
