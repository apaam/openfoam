#!/usr/bin/env bash
# Build one phynexis_foam-*.whl into BUILD_WHEEL_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

WHEEL_DIR="${WHEEL_OUT:-${BUILD_WHEEL_DIR}}"
case "${WHEEL_DIR}" in
/*) ;;
*) WHEEL_DIR="${ROOT}/${WHEEL_DIR}" ;;
esac

# setuptools build-base — must not wipe OPENFOAM_CLI_BUILD (cli-build/).
WHEEL_TMP="$(openfoam_abs_under_root "${ROOT}" "${BUILD_WHEEL_TMP_DIR}")"
STAGING_DIR="$(openfoam_abs_under_root "${ROOT}" "${BUILD_WHEEL_STAGE_DIR}")"
CLI_SRC="${ROOT}/cli"
BUILD_PY="${BUILD_PY:-python3}"
PKG_VERSION="${OPENFOAM_VERSION:-v2412}"
PKG_VERSION="${PKG_VERSION#v}"

sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

mkdir -p "${WHEEL_DIR}"
STAMP="${WHEEL_DIR}/.wheel-stamp"
existing_whl="$(ls -t "${WHEEL_DIR}"/phynexis_foam-*.whl 2>/dev/null | head -1 || true)"
if [[ -n "${existing_whl}" && -f "${STAMP}" && "${existing_whl}" -nt "${STAMP}" \
  && "$(<"${STAMP}")" == "${PKG_VERSION}" ]]; then
  printf '[wheel] Up to date: %s\n' "${existing_whl}"
  exit 0
fi

openfoam_safe_rm "${STAGING_DIR}"
openfoam_safe_rm "${WHEEL_TMP}"
openfoam_safe_rm "${CLI_SRC}/build"
mkdir -p "${STAGING_DIR}/phynexis_foam" "${STAGING_DIR}/completions/bash" "${WHEEL_TMP}"

cp "${CLI_SRC}/phynexis_foam/"*.py "${STAGING_DIR}/phynexis_foam/"
cp "${CLI_SRC}/completions/bash/phynexis-foam" "${STAGING_DIR}/completions/bash/phynexis-foam"
cp "${CLI_SRC}/pyproject.toml" "${STAGING_DIR}/"
cp "${CLI_SRC}/setup.py" "${STAGING_DIR}/"
cat >"${STAGING_DIR}/setup.cfg" <<EOF
[build]
build-base=${WHEEL_TMP}
EOF
sed_inplace -E "s/^__version__ = \".*\"/__version__ = \"${PKG_VERSION}\"/" \
  "${STAGING_DIR}/phynexis_foam/__init__.py"
sed_inplace -E "s/^version = \".*\"/version = \"${PKG_VERSION}\"/" \
  "${STAGING_DIR}/pyproject.toml"

for script in phynexis-foam.sh prefix.sh native.sh docker_run.sh shell_prompt.sh \
  shell_bashrc.sh _phynexis-foam completion.bash completion.zsh rewrite_openfoam_paths.sh manifest.sh; do
  src="${CLI_SRC}/phynexis_foam/${script}"
  [[ "${script}" == rewrite_openfoam_paths.sh ]] && src="${ROOT}/scripts/rewrite_openfoam_paths.sh"
  cp "${src}" "${STAGING_DIR}/phynexis_foam/${script}"
  chmod +x "${STAGING_DIR}/phynexis_foam/${script}"
done

# shellcheck source=../cli/phynexis_foam/manifest.sh
source "${ROOT}/cli/phynexis_foam/manifest.sh"
write_cli_manifest "${STAGING_DIR}/phynexis_foam/manifest.json" "wheel" 0 "${PKG_VERSION}"

rm -f "${WHEEL_DIR}"/phynexis_foam-*.whl "${WHEEL_DIR}"/openfoam_cli-*.whl \
  "${WHEEL_DIR}"/openfoam-*.whl 2>/dev/null || true

wheel_pip_status=0
(
  cd "${STAGING_DIR}"
  for path in phynexis_foam.egg-info dist; do
    openfoam_safe_rm "${path}"
  done
  if ! "${BUILD_PY}" -m pip wheel . -w "${WHEEL_DIR}" --no-cache-dir \
    --config-settings=--build-option=--keep-temp; then
    wheel_pip_status=$?
    whl="$(ls -t "${WHEEL_DIR}"/phynexis_foam-*.whl 2>/dev/null | head -1 || true)"
    if [[ -z "${whl}" ]]; then
      exit "${wheel_pip_status}"
    fi
    echo "[wheel] pip exited ${wheel_pip_status} during temp cleanup; wheel OK: ${whl}" >&2
  fi
) || exit $?

openfoam_safe_rm "${STAGING_DIR}"
openfoam_safe_rm "${WHEEL_TMP}"
printf '%s\n' "${PKG_VERSION}" >"${STAMP}"
printf '[wheel] -> %s/phynexis_foam-*.whl\n' "${WHEEL_DIR}"
