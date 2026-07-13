# Refuse docker-* (and other host-docker) entrypoints inside a container.
# Usage: source this file, then openfoam_require_docker_host [label]

openfoam_require_docker_host() {
  local label="${1:-docker-*}"
  if [[ -f /.dockerenv ]] || [[ "${PWD:-}" == "/src" ]]; then
    cat >&2 <<EOF
[${label}] Run on the host only, not inside docker-shell / compile container.
  Inside shell: make openfoam / make dist-native
  On host:      make ${label}
EOF
    return 1
  fi
  return 0
}
