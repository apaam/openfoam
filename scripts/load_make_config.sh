#!/usr/bin/env bash
# Load docs/make-config-default.mk and make-config-user.mk into the shell environment.
# Precedence: explicit environment variables > make-config-user.mk > make-config-default.mk
# CONTAINER_BUILD=1 path remapping is applied by openfoam_load_build_paths (not here).

load_make_config() {
  local root="${1:-}"
  if [[ -z "${root}" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi

  local f line key val
  for f in docs/make-config-default.mk make-config-user.mk; do
    [[ -f "${root}/${f}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%%#*}"
      line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
      [[ -z "${line}" ]] && continue
      [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(:|\?)?=[[:space:]]* ]] || continue
      key="$(printf '%s' "${line}" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(:|\?)?=[[:space:]]*.*/\1/')"
      val="$(printf '%s' "${line}" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(:|\?)?=[[:space:]]*(.*)/\3/')"
      val="${val%\"}"
      val="${val#\"}"
      val="${val%\'}"
      val="${val#\'}"
      if [[ -z "${!key+x}" ]]; then
        export "${key}=${val}"
      fi
    done < "${root}/${f}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_make_config "${1:-}"
  env | grep -E '^(BUILD_|DOCKER_)=' | sort
fi
