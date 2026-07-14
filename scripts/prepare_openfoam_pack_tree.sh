#!/usr/bin/env bash
# Prepare product pack tree: openfoam/ (OF) + etc/bashrc + embedded CLI.
# OPENFOAM_STAGE_OVERRIDE=... redirects the product dest (used by make install).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

_bundle_override="${OPENFOAM_BUNDLE_RUNTIME+x}"
_saved_bundle="${OPENFOAM_BUNDLE_RUNTIME-}"
openfoam_load_build_paths "${ROOT}"
if [[ -n "${_bundle_override}" ]]; then
  export OPENFOAM_BUNDLE_RUNTIME="${_saved_bundle}"
else
  export OPENFOAM_BUNDLE_RUNTIME="${OPENFOAM_BUNDLE_RUNTIME:-0}"
fi

OPENFOAM_BUILD="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_BUILD}")"
if [[ -n "${OPENFOAM_STAGE_OVERRIDE:-}" ]]; then
  OPENFOAM_STAGE="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_STAGE_OVERRIDE}")"
else
  OPENFOAM_STAGE="$(openfoam_abs_under_root "${ROOT}" "${OPENFOAM_STAGE}")"
fi
FORCE_STAGE="${FORCE_STAGE:-0}"
OF_DEST="${OPENFOAM_STAGE}/openfoam"

# Clear pack stage before restage: FORCE wipes all; otherwise keep openfoam/ for
# incremental rsync and drop everything else (etc/bin/share/stamps).
if [[ "${FORCE_STAGE}" == "1" ]]; then
  echo "[prepare_openfoam_pack_tree] Force clean ${OPENFOAM_STAGE}"
  openfoam_safe_rm "${OPENFOAM_STAGE}"
else
  mkdir -p "${OPENFOAM_STAGE}"
  shopt -s nullglob
  for _path in "${OPENFOAM_STAGE}"/* "${OPENFOAM_STAGE}"/.[!.]* "${OPENFOAM_STAGE}"/..?*; do
    [[ -e "${_path}" ]] || continue
    case "$(basename "${_path}")" in
    openfoam) continue ;;
    esac
    openfoam_safe_rm "${_path}"
  done
  shopt -u nullglob
  unset _path
fi
mkdir -p "${OPENFOAM_STAGE}"

export FORCE_STAGE
bash "${ROOT}/scripts/stage_openfoam.sh" "${OPENFOAM_BUILD}" "${OPENFOAM_STAGE}"

OLD_OF="$(cd "${OPENFOAM_BUILD}" && pwd)"
NEW_OF="$(cd "${OF_DEST}" && pwd)"
PRODUCT="$(cd "${OPENFOAM_STAGE}" && pwd)"

bash "${ROOT}/scripts/rewrite_openfoam_paths.sh" \
  "${NEW_OF}" "${OLD_OF}" "${NEW_OF}"

if [[ "${OPENFOAM_BUNDLE_RUNTIME}" =~ ^(1|yes|true|on)$ ]]; then
  bash "${ROOT}/scripts/bundle_openfoam_runtime.sh" "${NEW_OF}"
  bash "${ROOT}/scripts/ensure_bundled_libpmix.sh" "${NEW_OF}"
  bash "${ROOT}/scripts/rewrite_openfoam_prefs.sh" "${NEW_OF}"
else
  openfoam_safe_rm "${NEW_OF}/lib"
  echo "[prepare_openfoam_pack_tree] Skipping runtime bundle (OPENFOAM_BUNDLE_RUNTIME=${OPENFOAM_BUNDLE_RUNTIME})"
fi

bash "${ROOT}/scripts/install_dist_bashrc.sh" "${PRODUCT}"
bash "${ROOT}/scripts/verify_openfoam_pack.sh" "${PRODUCT}"

# CLI at product root; OF under openfoam/.
OPENFOAM_VERSION="${OPENFOAM_VERSION:-v2412}" \
  bash "${ROOT}/scripts/install_openfoam_cli.sh" "${PRODUCT}" "${NEW_OF}"

printf '%s\n' "${PRODUCT}" > "${PRODUCT}/.pack-source-prefix"
{
  printf 'bundle=%s\n' "${OPENFOAM_BUNDLE_RUNTIME}"
  date -u +%Y-%m-%dT%H:%M:%SZ
} > "${PRODUCT}/.pack-stamp"
echo "[prepare_openfoam_pack_tree] Ready at ${PRODUCT} (of=${NEW_OF}, bundle=${OPENFOAM_BUNDLE_RUNTIME})"
