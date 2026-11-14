#!/usr/bin/env bash
# Container backend plugin.
#
# Everything under docker/*.sh calls `cb <docker-cli-syntax>`. Which CLI runs
# is selected by CONTAINER_BACKEND:
#
#   auto    (default) docker -> podman -> apple, first available wins
#   docker  Docker Engine / Docker Desktop (buildx for --platform builds)
#   podman  Podman (native `podman build`; same CLI surface for run/image)
#   apple   Apple `container` (macOS 26+; --arch replaces --platform, and
#           --rosetta is added for linux/amd64 on Apple Silicon)
#
# Only this file knows backend-specific syntax. Add a backend by writing
# _cb_<name> and extending _cb_detect.

_cb_backend="${CONTAINER_BACKEND:-auto}"
_cb_resolved=""

_cb_detect() {
  [[ -n "${_cb_resolved}" ]] && return 0
  case "${_cb_backend}" in
    auto)
      if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        _cb_resolved=docker
      elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        _cb_resolved=podman
      elif command -v container >/dev/null 2>&1; then
        _cb_resolved=apple
      else
        _cb_resolved=none
      fi
      ;;
    docker | podman | apple)
      _cb_resolved="${_cb_backend}"
      ;;
    *)
      echo "[container] unknown CONTAINER_BACKEND=${_cb_backend}" >&2
      _cb_resolved=none
      ;;
  esac
}

openfoam_container_backend() {
  _cb_detect
  printf '%s\n' "${_cb_resolved}"
}

openfoam_require_container() {
  _cb_detect
  case "${_cb_resolved}" in
    docker)
      if ! command -v docker >/dev/null 2>&1; then
        echo "Docker not found. Install Docker Desktop or Docker Engine first." >&2
        return 1
      fi
      if ! docker info >/dev/null 2>&1; then
        echo "Docker is installed but not running. Start Docker Desktop (or the daemon) and retry." >&2
        return 1
      fi
      ;;
    podman)
      if ! command -v podman >/dev/null 2>&1; then
        echo "Podman not found." >&2
        return 1
      fi
      if ! podman info >/dev/null 2>&1; then
        echo "Podman is installed but not running. Run 'podman machine start' and retry." >&2
        return 1
      fi
      ;;
    apple)
      if ! command -v container >/dev/null 2>&1; then
        echo "Apple container CLI not found." >&2
        return 1
      fi
      ;;
    *)
      echo "No container backend available (tried docker, podman, container)." >&2
      echo "Set CONTAINER_BACKEND=docker|podman|apple to pick one explicitly." >&2
      return 1
      ;;
  esac
  return 0
}

# Backwards-compatible name used by older call sites.
openfoam_require_docker() { openfoam_require_container "$@"; }

cb() {
  _cb_detect
  case "${_cb_resolved}" in
    docker) docker "$@" ;;
    podman) _cb_podman "$@" ;;
    apple) _cb_apple "$@" ;;
    *)
      echo "[container] no backend (CONTAINER_BACKEND=${_cb_backend})" >&2
      return 1
      ;;
  esac
}

# --- podman ---------------------------------------------------------------

_cb_podman() {
  case "${1:-} ${2:-}" in
    "buildx build")
      shift 2
      podman build "$@"
      ;;
    "buildx version")
      podman --version >/dev/null
      ;;
    "buildx imagetools")
      shift 2
      if ! command -v skopeo >/dev/null 2>&1; then
        echo "[container] podman backend needs skopeo for 'buildx imagetools inspect'" >&2
        return 1
      fi
      local ref="" a
      for a in "$@"; do
        case "${a}" in
          --*) ;;
          *) ref="${a}" ;;
        esac
      done
      skopeo inspect --raw "docker://${ref}"
      ;;
    *) podman "$@" ;;
  esac
}

# --- Apple container ------------------------------------------------------

_cb_apple() {
  local verb="${1:-}"
  shift || true
  case "${verb}" in
    info) container system status >/dev/null 2>&1 ;;
    run) _cb_apple_run "$@" ;;
    image) _cb_apple_image "$@" ;;
    tag) _cb_apple_image tag "$@" ;;
    rmi) _cb_apple_image delete "$@" ;;
    pull) _cb_apple_pull "$@" ;;
    buildx) _cb_apple_buildx "$@" ;;
    save)
      echo "[container] apple backend does not support 'save'; use CONTAINER_BACKEND=docker" >&2
      return 1
      ;;
    *)
      echo "[container] apple backend: unsupported verb '${verb}'" >&2
      return 1
      ;;
  esac
}

_cb_apple_run() {
  local -a out=(container run)
  local platform=""
  while (($#)); do
    case "$1" in
      --platform)
        platform="${2#linux/}"
        out+=(--arch "${platform}")
        shift 2
        ;;
      -v | --volume)
        out+=(--volume "$2")
        shift 2
        ;;
      -w | --workdir)
        out+=(--workdir "$2")
        shift 2
        ;;
      -e | --env)
        out+=(--env "$2")
        shift 2
        ;;
      -it)
        out+=(-t -i)
        shift
        ;;
      *)
        out+=("$1")
        shift
        ;;
    esac
  done
  if [[ "${platform}" == "amd64" && "$(uname -m)" == "arm64" ]]; then
    out+=(--rosetta)
  fi
  "${out[@]}"
}

_cb_apple_image() {
  container image "$@"
}

_cb_apple_pull() {
  local -a out=(container image pull)
  while (($#)); do
    case "$1" in
      --platform) out+=(--arch "${2#linux/}"); shift 2 ;;
      *) out+=("$1"); shift ;;
    esac
  done
  "${out[@]}"
}

_cb_apple_buildx() {
  case "${1:-}" in
    version) container builder status >/dev/null 2>&1 ;;
    build)
      shift
      local -a out=(container build)
      while (($#)); do
        case "$1" in
          --platform) out+=(--arch "${2#linux/}"); shift 2 ;;
          -f | --file) out+=(--file "$2"); shift 2 ;;
          -t | --tag) out+=(--tag "$2"); shift 2 ;;
          *) out+=("$1"); shift ;;
        esac
      done
      "${out[@]}"
      ;;
    *)
      echo "[container] apple backend: unsupported 'buildx $1'" >&2
      return 1
      ;;
  esac
}
