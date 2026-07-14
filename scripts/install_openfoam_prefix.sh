#!/usr/bin/env bash
# Install from pack/ (tar → INSTALL_PREFIX) and/or wheel/ (pip).
# Options: INSTALL_PACK=0|1 INSTALL_WHEEL=0|1 (default 1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

PREFIX="${INSTALL_PREFIX:-install}"
PREFIX="$(openfoam_abs_under_root "${ROOT}" "${PREFIX}")"
PACK_DIR="$(openfoam_abs_under_root "${ROOT}" "${BUILD_PACK_DIR}")"
WHEEL_DIR="$(openfoam_abs_under_root "${ROOT}" "${BUILD_WHEEL_DIR}")"
WHEEL_MATCH="${BUILD_WHEEL_MATCH:-openfoam_cli-*.whl}"
BUILD_PY="${BUILD_PY:-python3}"
INSTALL_PACK="${INSTALL_PACK:-1}"
INSTALL_WHEEL="${INSTALL_WHEEL:-1}"

if [[ ! "${INSTALL_PACK}" =~ ^(1|yes|true|on)$ ]] \
  && [[ ! "${INSTALL_WHEEL}" =~ ^(1|yes|true|on)$ ]]; then
  echo "[install] Both INSTALL_PACK and INSTALL_WHEEL are off" >&2
  exit 1
fi

find_archive() {
  local f
  f="$(ls -t "${PACK_DIR}"/openfoam-native-*.tar.gz 2>/dev/null | head -1 || true)"
  if [[ -z "${f}" ]]; then
    echo "[install] No openfoam-native-*.tar.gz under ${PACK_DIR}" >&2
    echo "[install] Run: make pack" >&2
    return 1
  fi
  printf '%s' "${f}"
}

find_wheel() {
  local f
  f="$(ls -t "${WHEEL_DIR}"/${WHEEL_MATCH} 2>/dev/null | head -1 || true)"
  if [[ -z "${f}" ]]; then
    echo "[install] No ${WHEEL_MATCH} under ${WHEEL_DIR}" >&2
    echo "[install] Run: make wheel" >&2
    return 1
  fi
  printf '%s' "${f}"
}

if [[ "${INSTALL_PACK}" =~ ^(1|yes|true|on)$ ]]; then
  ARCHIVE="$(find_archive)"
  if [[ -d "${PREFIX}" ]]; then
    openfoam_safe_rm "${PREFIX}"
  fi
  mkdir -p "${PREFIX}"
  echo "[install] pack ${ARCHIVE}"
  echo "[install] -> ${PREFIX}"
  tar xzf "${ARCHIVE}" -C "${PREFIX}"

  if [[ ! -f "${PREFIX}/etc/bashrc" ]]; then
    echo "[install] Missing ${PREFIX}/etc/bashrc after extract" >&2
    exit 1
  fi
  if [[ ! -f "${PREFIX}/openfoam/etc/bashrc" ]]; then
    echo "[install] Missing ${PREFIX}/openfoam/etc/bashrc after extract" >&2
    exit 1
  fi

  OLD_PREFIX=""
  if [[ -f "${PREFIX}/.pack-source-prefix" ]]; then
    OLD_PREFIX="$(tr -d '\n' <"${PREFIX}/.pack-source-prefix")"
  fi
  NEW_PREFIX="$(cd "${PREFIX}" && pwd)"
  if [[ -n "${OLD_PREFIX}" && "${OLD_PREFIX}" != "${NEW_PREFIX}" ]]; then
    bash "${ROOT}/scripts/rewrite_openfoam_paths.sh" \
      "${NEW_PREFIX}/openfoam" "${OLD_PREFIX}" "${NEW_PREFIX}"
  fi
  printf '%s\n' "${NEW_PREFIX}" >"${NEW_PREFIX}/.pack-source-prefix"
  rm -f "${NEW_PREFIX}/.prefix-rewritten"
  echo "[install] Pack installed at ${NEW_PREFIX}"
  echo "[install] export OPENFOAM_PREFIX=${NEW_PREFIX}"
  echo "[install] source \"\${OPENFOAM_PREFIX}/etc/bashrc\""
fi

if [[ "${INSTALL_WHEEL}" =~ ^(1|yes|true|on)$ ]]; then
  WHL="$(find_wheel)"
  echo "[install] wheel ${WHL}"
  "${BUILD_PY}" -m pip install --force-reinstall "${WHL}"
fi

echo "[install] Done"
