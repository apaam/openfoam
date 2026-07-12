#!/usr/bin/env bash
# Platform prefs live under build/meta/ and are applied into OPENFOAM_BUILD/etc/.

openfoam_meta_dir() {
  printf '%s/build/meta' "$1"
}

openfoam_meta_prefs_key() {
  printf '%s.%s' "${1##*/}" "$2"
}

openfoam_tracked_meta_prefs() {
  local root="$1" build_dir="$2" platform="$3"
  printf '%s/meta/%s.prefs.sh' \
    "${root}" "$(openfoam_meta_prefs_key "${build_dir}" "${platform}")"
}

openfoam_runtime_meta_prefs() {
  local root="$1" build_dir="$2" platform="$3"
  printf '%s/%s.prefs.sh' \
    "$(openfoam_meta_dir "${root}")" "$(openfoam_meta_prefs_key "${build_dir}" "${platform}")"
}

openfoam_runtime_meta_prefs_csh() {
  local root="$1" build_dir="$2" platform="$3"
  printf '%s/%s.prefs.csh' \
    "$(openfoam_meta_dir "${root}")" "$(openfoam_meta_prefs_key "${build_dir}" "${platform}")"
}

openfoam_prepare_linux_meta() {
  local root="$1" build_dir="$2"
  local template runtime

  template="$(openfoam_tracked_meta_prefs "${root}" "${build_dir}" linux)"
  runtime="$(openfoam_runtime_meta_prefs "${root}" "${build_dir}" linux)"
  mkdir -p "$(openfoam_meta_dir "${root}")"
  if [[ ! -f "${template}" ]]; then
    echo "[build_openfoam] Missing tracked meta template: ${template}" >&2
    exit 1
  fi
  cp "${template}" "${runtime}"
}

openfoam_apply_meta_prefs() {
  local root="$1" build_dir="$2" platform="$3"
  local src_sh="${build_dir}/etc/prefs.sh"
  local meta_sh meta_csh

  meta_sh="$(openfoam_runtime_meta_prefs "${root}" "${build_dir}" "${platform}")"
  if [[ ! -f "${meta_sh}" ]]; then
    echo "[build_openfoam] Missing runtime meta prefs: ${meta_sh}" >&2
    exit 1
  fi
  mkdir -p "${build_dir}/etc"
  cp "${meta_sh}" "${src_sh}"

  meta_csh="$(openfoam_runtime_meta_prefs_csh "${root}" "${build_dir}" "${platform}")"
  if [[ -f "${meta_csh}" ]]; then
    cp "${meta_csh}" "${build_dir}/etc/prefs.csh"
  else
    rm -f "${build_dir}/etc/prefs.csh"
  fi
  echo "[build_openfoam] Applied meta prefs ${meta_sh} -> ${src_sh}"
}

darwin_meta_need_configure() {
  local root="$1" build_dir="$2"
  local meta_sh applied_sh

  meta_sh="$(openfoam_runtime_meta_prefs "${root}" "${build_dir}" darwin)"
  applied_sh="${build_dir}/etc/prefs.sh"

  [[ ! -f "${meta_sh}" ]] && return 0
  [[ "${root}/Brewfile" -nt "${meta_sh}" ]] && return 0
  [[ "${root}/configure.sh" -nt "${meta_sh}" ]] && return 0

  if [[ -f "${applied_sh}" ]] \
    && grep -q '^export WM_COMPILER=Gcc$' "${applied_sh}" \
    && ! grep -q '^export CPATH=' "${applied_sh}"; then
    return 0
  fi
  return 1
}

platform_meta_config_changed() {
  local root="$1" build_dir="$2" platform="$3"

  case "${platform}" in
  darwin)
    darwin_meta_need_configure "${root}" "${build_dir}" && return 0
    ;;
  linux)
    local template applied
    template="$(openfoam_tracked_meta_prefs "${root}" "${build_dir}" linux)"
    applied="${build_dir}/etc/prefs.sh"
    [[ ! -f "${applied}" ]] && return 0
    [[ "${template}" -nt "${applied}" ]] && return 0
    ;;
  esac
  return 1
}

linux_sync_etc_from_source() {
  local src="$1" build_dir="$2"
  local f

  for f in etc/bashrc etc/cshrc; do
    if [[ -f "${src}/${f}" ]]; then
      rsync -a "${src}/${f}" "${build_dir}/${f}"
    fi
  done
}

linux_cleanup_stale_platforms() {
  local build_dir="$1"

  if [[ -d "${build_dir}/platforms" ]] \
    && compgen -G "${build_dir}/platforms/*Clang*" >/dev/null; then
    echo "[build_openfoam] Removing stale Clang platform artifacts"
    rm -rf "${build_dir}"/platforms/*Clang* "${build_dir}/wmake/build"
  fi
}
