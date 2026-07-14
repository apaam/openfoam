#!/usr/bin/env bash
# Host-side guards for docker-* entrypoints.
# Usage: source this file, then:
#   openfoam_require_docker_host [label]
#   openfoam_require_docker

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

openfoam_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not found. Install Docker Desktop or Docker Engine first." >&2
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but not running. Start Docker Desktop (or the daemon) and retry." >&2
    return 1
  fi
  return 0
}
