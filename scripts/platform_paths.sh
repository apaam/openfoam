#!/usr/bin/env bash
# Shared path resolution (no hardcoded Homebrew prefixes).

platform_paths_brew_prefix() {
  command -v brew >/dev/null 2>&1 || return 1
  brew --prefix 2>/dev/null
}

platform_paths_brew_bin() {
  local prefix
  prefix="$(platform_paths_brew_prefix)" || return 1
  printf '%s/bin' "${prefix}"
}

# Bash 4.3+ for OpenFOAM wmake (wait -n). Prefer PATH / OPENFOAM_BASH override.
platform_paths_resolve_bash() {
  local candidate
  for candidate in "${OPENFOAM_BASH:-}" "$(command -v bash 2>/dev/null)"; do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    if "${candidate}" -c \
      '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) ))' \
      2>/dev/null; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  command -v bash 2>/dev/null || printf '%s' /bin/bash
}

# One path per line: brew lib dirs for dylib/rpath search (macOS packaging).
platform_paths_brew_lib_dirs() {
  local prefix libdir
  prefix="$(platform_paths_brew_prefix)" || return 0
  [[ -d "${prefix}/lib" ]] && printf '%s\n' "${prefix}/lib"
  for libdir in "${prefix}"/opt/*/lib; do
    [[ -d "${libdir}" ]] && printf '%s\n' "${libdir}"
  done
}
