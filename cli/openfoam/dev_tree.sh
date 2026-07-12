#!/usr/bin/env bash
# Install or partially remove OpenFOAM under OPENFOAM_PREFIX from openfoam-prefix.tar.gz.

set -euo pipefail

DEV_TREE_ITEMS=(src applications wmake)
INSTALL_STAMP=".openfoam-install-stamp"
PREFIX_ARCHIVE="openfoam-prefix.tar.gz"
DEFAULT_DEV_PREFIX="${DEFAULT_OPENFOAM_PREFIX:-/opt/openfoam}"

_dev_safe_rm() {
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

resolve_dev_prefix() {
  if [[ -n "${OPENFOAM_PREFIX:-}" ]]; then
    mkdir -p "${OPENFOAM_PREFIX}"
    OPENFOAM_PREFIX="$(cd "${OPENFOAM_PREFIX}" && pwd)"
  else
    OPENFOAM_PREFIX="${DEFAULT_DEV_PREFIX}"
    if ! mkdir -p "${OPENFOAM_PREFIX}" 2>/dev/null; then
      cat >&2 <<EOF
Cannot create ${DEFAULT_DEV_PREFIX} (try sudo or set OPENFOAM_PREFIX).

Example:
  export OPENFOAM_PREFIX=/Volumes/OpenFOAM/opt/openfoam
  openfoam dev install
EOF
      exit 1
    fi
    OPENFOAM_PREFIX="$(cd "${OPENFOAM_PREFIX}" && pwd)"
  fi
  export OPENFOAM_PREFIX
}

find_prefix_tar() {
  local dir="${SCRIPT_DIR}"
  if [[ -f "${dir}/${PREFIX_ARCHIVE}" ]]; then
    printf '%s' "${dir}/${PREFIX_ARCHIVE}"
    return 0
  fi
  return 1
}

dev_usage() {
  cat <<EOF
${CLI_PREFIX} dev — install OpenFOAM to OPENFOAM_PREFIX

  install                         Extract openfoam-prefix.tar.gz (full install tree)
  clean                           Remove src, applications, wmake from OPENFOAM_PREFIX

OPENFOAM_PREFIX sets the install root (default: ${DEFAULT_DEV_PREFIX}).
Wheel installs CLI only; dev install populates the prefix (same layout as cpack).

Examples:
  pip install openfoam-*.whl
  export OPENFOAM_PREFIX=/Volumes/OpenFOAM/opt/openfoam
  openfoam dev install
  source \${OPENFOAM_PREFIX}/etc/bashrc
  openfoam dev clean
EOF
}

cmd_dev_install() {
  local tar=""
  resolve_dev_prefix
  if ! tar="$(find_prefix_tar)"; then
    echo "Missing ${PREFIX_ARCHIVE}; pip install openfoam-*.whl (make wheel-install)" >&2
    exit 1
  fi
  mkdir -p "${OPENFOAM_PREFIX}"
  echo "[openfoam dev install] ${OPENFOAM_PREFIX} <- ${tar}"
  tar -xzf "${tar}" -C "${OPENFOAM_PREFIX}"
  rewrite_installed_prefix "${OPENFOAM_PREFIX}"
  date -u +%Y-%m-%dT%H:%M:%SZ >"${OPENFOAM_PREFIX}/${INSTALL_STAMP}"
}

cmd_dev_clean() {
  local item
  resolve_dev_prefix
  for item in "${DEV_TREE_ITEMS[@]}"; do
    _dev_safe_rm "${OPENFOAM_PREFIX}/${item}"
  done
  rm -f "${OPENFOAM_PREFIX}/${INSTALL_STAMP}"
  echo "[openfoam dev clean] removed src applications wmake under ${OPENFOAM_PREFIX}"
}

cmd_dev() {
  local action="${1:-}"
  shift || true
  case "${action}" in
  install) cmd_dev_install "$@" ;;
  clean) cmd_dev_clean "$@" ;;
  -h | --help | help | "") dev_usage ;;
  *)
    echo "Unknown dev command: ${action}" >&2
    dev_usage >&2
    exit 1
    ;;
  esac
}
