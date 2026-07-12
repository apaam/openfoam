#!/usr/bin/env bash
# Platform prefs helpers. Final prefs always live in OPENFOAM_BUILD/etc/.

darwin_need_configure() {
  local root="$1" build_dir="$2"
  local applied_sh="${build_dir}/etc/prefs.sh"

  [[ ! -f "${applied_sh}" ]] && return 0
  [[ "${root}/Brewfile" -nt "${applied_sh}" ]] && return 0
  [[ "${root}/configure.sh" -nt "${applied_sh}" ]] && return 0

  # Stale linux/Gcc prefs left in a darwin tree.
  if grep -q '^export WM_COMPILER=Gcc$' "${applied_sh}" \
    && ! grep -q '^export CPATH=' "${applied_sh}"; then
    return 0
  fi
  return 1
}

linux_write_prefs() {
  local build_dir="$1"
  mkdir -p "${build_dir}/etc"
  printf '%s\n' 'export WM_COMPILER=Gcc' > "${build_dir}/etc/prefs.sh"
  rm -f "${build_dir}/etc/prefs.csh"
  echo "[build_openfoam] Wrote ${build_dir}/etc/prefs.sh (WM_COMPILER=Gcc)"
}

platform_config_changed() {
  local root="$1" build_dir="$2" platform="$3"

  case "${platform}" in
  darwin)
    darwin_need_configure "${root}" "${build_dir}" && return 0
    ;;
  linux)
    local applied="${build_dir}/etc/prefs.sh"
    [[ ! -f "${applied}" ]] && return 0
    grep -qx 'export WM_COMPILER=Gcc' "${applied}" || return 0
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

darwin_cleanup_foreign_platforms() {
  local build_dir="$1"

  if compgen -G "${build_dir}/platforms/linuxARM64*" >/dev/null; then
    echo "[build_openfoam] Removing foreign linuxARM64 platform artifacts"
    rm -rf "${build_dir}"/platforms/linuxARM64* "${build_dir}"/build/linuxARM64*
  fi
}
