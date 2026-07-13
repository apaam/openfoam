#!/usr/bin/env bash
# Load docs/make-config-default.mk and make-config-user.mk into the shell environment.
# Precedence: explicit environment variables > make-config-user.mk > make-config-default.mk
# Make-style $(NAME) refs are expanded after both files are read.
# CONTAINER_BUILD=1 path remapping is applied by openfoam_load_build_paths (not here).

# Expand $(NAME) using already-exported variables (make-style, shallow).
load_make_config_expand_refs() {
  local val="$1"
  local name ref
  local guard=0
  while [[ "${val}" =~ \$\(([A-Za-z_][A-Za-z0-9_]*)\) ]] && ((guard++ < 20)); do
    name="${BASH_REMATCH[1]}"
    ref="${!name-}"
    val="${val//\$($name)/${ref}}"
  done
  printf '%s' "${val}"
}

# Collect KEY= / KEY:= / KEY?= assignment keys from a make-config file.
load_make_config_keys_from_file() {
  local file="$1"
  local line key
  [[ -f "${file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(:|\?)?=[[:space:]]* ]] || continue
    key="$(printf '%s' "${line}" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(:|\?)?=[[:space:]]*.*/\1/')"
    printf '%s\n' "${key}"
  done < "${file}"
}

load_make_config_is_locked() {
  local key="$1"
  local locked="$2"
  printf '%s\n' "${locked}" | grep -qxF "${key}"
}

load_make_config() {
  local root="${1:-}"
  if [[ -z "${root}" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi

  local f line key val
  local -a deferred_keys=() deferred_vals=()
  local env_locked=""
  local i

  # Snapshot keys already present in the environment (those win over both files).
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    if [[ -n "${!key+x}" ]]; then
      env_locked="${env_locked}${key}"$'\n'
    fi
  done < <(
    load_make_config_keys_from_file "${root}/docs/make-config-default.mk"
    load_make_config_keys_from_file "${root}/make-config-user.mk"
  )

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
      if load_make_config_is_locked "${key}" "${env_locked}"; then
        continue
      fi
      if [[ "${val}" == *'$('* ]]; then
        # Later file wins: replace prior deferred entry for this key.
        for i in "${!deferred_keys[@]}"; do
          if [[ "${deferred_keys[$i]}" == "${key}" ]]; then
            deferred_vals[$i]="${val}"
            continue 2
          fi
        done
        deferred_keys+=("${key}")
        deferred_vals+=("${val}")
        continue
      fi
      # Concrete assignment clears any earlier deferred value for this key.
      for i in "${!deferred_keys[@]}"; do
        if [[ "${deferred_keys[$i]}" == "${key}" ]]; then
          deferred_keys[$i]=""
        fi
      done
      export "${key}=${val}"
    done < "${root}/${f}"
  done

  local expanded
  for i in "${!deferred_keys[@]}"; do
    key="${deferred_keys[$i]}"
    [[ -n "${key}" ]] || continue
    if load_make_config_is_locked "${key}" "${env_locked}"; then
      continue
    fi
    expanded="$(load_make_config_expand_refs "${deferred_vals[$i]}")"
    export "${key}=${expanded}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_make_config "${1:-}"
  env | grep -E '^(BUILD_|DOCKER_|OPENFOAM_|DIST_)' | sort
fi
