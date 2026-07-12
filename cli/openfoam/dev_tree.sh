#!/usr/bin/env bash
# Install or remove the full OpenFOAM prefix under OPENFOAM_PREFIX from openfoam-prefix.tar.gz.

set -euo pipefail

INSTALL_STAMP=".openfoam-install-stamp"
PREFIX_ARCHIVE="openfoam-prefix.tar.gz"
DEFAULT_DEV_PREFIX="${DEFAULT_OPENFOAM_PREFIX:-/opt/openfoam}"

_prefix_case_sensitive() {
  local dir="$1" probe
  [[ -d "${dir}" ]] || return 0
  probe="$(mktemp -d "${dir}/.case-probe.XXXXXX")"
  rm -f "${probe}/probe_a" "${probe}/PROBE_A"
  touch "${probe}/probe_a"
  if [[ -e "${probe}/PROBE_A" ]]; then
    _dev_safe_rm "${probe}"
    return 1
  fi
  _dev_safe_rm "${probe}"
  return 0
}

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

_ln_include_ready() {
  local prefix="$1"
  local header

  for header in \
    "${prefix}/src/OpenFOAM/lnInclude/addToRunTimeSelectionTable.H" \
    "${prefix}/src/finiteVolume/lnInclude/volFields.H" \
    "${prefix}/src/meshTools/lnInclude/fixedJumpFvPatchField.H"
  do
    [[ -e "${header}" ]] || return 1
  done
  return 0
}

_restore_ln_include() {
  local prefix="$1"
  local tool="${prefix}/wmake/wmakeLnIncludeAll"
  local -a force_args=()

  [[ -x "${tool}" ]] || return 0
  _ln_include_ready "${prefix}" && return 0

  if [[ -d "${prefix}/src/OpenFOAM/lnInclude" ]]; then
    force_args=(-force)
  fi

  echo "[openfoam dev install] Regenerating lnInclude (required for wmake) ..."
  (
    cd "${prefix}" || exit 1
    jobs="${WM_NCOMPPROCS:-${NUM_JOBS:-4}}"
    WM_PROJECT_DIR="${prefix}" \
    WM_NCOMPPROCS="${jobs}" \
    PATH="${prefix}/wmake:${PATH}" \
      bash "${tool}" "${force_args[@]}" -j"${jobs}" src applications
  ) || {
    echo "[openfoam dev install] lnInclude regeneration failed; check ${prefix}/wmake/wmakeLnIncludeAll" >&2
    exit 1
  }

  _ln_include_ready "${prefix}" || {
    echo "[openfoam dev install] lnInclude still incomplete after regeneration" >&2
    exit 1
  }
}

dev_usage() {
  cat <<EOF
${CLI_PREFIX} dev — install OpenFOAM to OPENFOAM_PREFIX

  install                         Install full OpenFOAM prefix from openfoam-prefix.tar.gz
  clean                           Remove entire OPENFOAM_PREFIX

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
  local tar="" prefix_tar=""
  resolve_dev_prefix
  if ! tar="$(find_prefix_tar)"; then
    echo "Missing ${PREFIX_ARCHIVE}; pip install openfoam-*.whl (make wheel-install)" >&2
    exit 1
  fi
  if [[ "$(uname -s)" == "Darwin" ]] && ! _prefix_case_sensitive "${OPENFOAM_PREFIX}"; then
    echo "Warning: ${OPENFOAM_PREFIX} is on a case-insensitive volume; use a case-sensitive path (e.g. /Volumes/OpenFOAM/opt/openfoam)." >&2
  fi
  _dev_safe_rm "${OPENFOAM_PREFIX}"
  mkdir -p "${OPENFOAM_PREFIX}"
  prefix_tar="${OPENFOAM_PREFIX}/.${PREFIX_ARCHIVE}"
  echo "[openfoam dev install] ${OPENFOAM_PREFIX} <- ${tar}"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    export COPYFILE_DISABLE=1
  fi
  cp -f "${tar}" "${prefix_tar}"
  tar -xzf "${prefix_tar}" -C "${OPENFOAM_PREFIX}" \
    --exclude='.DS_Store' \
    --exclude='*/.DS_Store'
  rm -f "${prefix_tar}"
  if [[ ! -f "${OPENFOAM_PREFIX}/etc/bashrc" ]]; then
    echo "[openfoam dev install] Missing ${OPENFOAM_PREFIX}/etc/bashrc after extract" >&2
    exit 1
  fi
  _restore_ln_include "${OPENFOAM_PREFIX}"
  rewrite_installed_prefix "${OPENFOAM_PREFIX}"
  date -u +%Y-%m-%dT%H:%M:%SZ >"${OPENFOAM_PREFIX}/${INSTALL_STAMP}"
}

cmd_dev_clean() {
  resolve_dev_prefix
  _dev_safe_rm "${OPENFOAM_PREFIX}"
  echo "[openfoam dev clean] removed ${OPENFOAM_PREFIX}"
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
