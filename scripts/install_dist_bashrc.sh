#!/usr/bin/env bash
# Install product etc/bashrc (sources openfoam/etc/bashrc).
# Usage: install_dist_bashrc.sh <product-prefix>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="${1:?product prefix required}"
ETC="${STAGE}/etc"
WRAPPER="${ETC}/bashrc"
OF_UPSTREAM="${STAGE}/openfoam/etc/bashrc"

resolve_template() {
  local cand
  for cand in \
    "${OPENFOAM_DIST_BASHRC:-}" \
    "${SCRIPT_DIR}/etc/bashrc" \
    "${SCRIPT_DIR}/../etc/bashrc" \
    /usr/local/share/openfoam/etc/bashrc
  do
    [[ -n "${cand}" && -f "${cand}" ]] || continue
    printf '%s' "${cand}"
    return 0
  done
  return 1
}

SRC="$(resolve_template)" || {
  echo "[install_dist_bashrc] Missing dist bashrc template" >&2
  exit 1
}

if [[ ! -f "${OF_UPSTREAM}" ]]; then
  echo "[install_dist_bashrc] Missing ${OF_UPSTREAM}" >&2
  exit 1
fi

mkdir -p "${ETC}"
cp -f "${SRC}" "${WRAPPER}"
chmod 644 "${WRAPPER}"
echo "[install_dist_bashrc] Installed ${WRAPPER} from ${SRC}"
