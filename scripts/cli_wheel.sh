#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/openfoam_build_paths.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

openfoam_load_build_paths "${ROOT}"

WHEEL_DIR="${WHEEL_OUT:-${BUILD_CLI_WHEEL_DIR:-build/cli-wheel}}"
case "${WHEEL_DIR}" in
/*) ;;
*) WHEEL_DIR="${ROOT}/${WHEEL_DIR}" ;;
esac

CLI_BUILD_DIR="${BUILD_CLI_BUILD_DIR:-build/cli-build}"
case "${CLI_BUILD_DIR}" in
/*) ;;
*) CLI_BUILD_DIR="${ROOT}/${CLI_BUILD_DIR}" ;;
esac

CLI_SRC="${ROOT}/cli"
STAGING_DIR="${ROOT}/build/stage/cli-wheel"
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
STAMP="${WHEEL_DIR}/.cli-wheel-stamp"
existing_whl="$(ls -t "${WHEEL_DIR}"/openfoam_cli-*.whl 2>/dev/null | head -1 || true)"
if [[ -n "${existing_whl}" && -f "${STAMP}" && "${existing_whl}" -nt "${STAMP}" \
  && "$(<"${STAMP}")" == "${PKG_VERSION}" ]]; then
  printf '[cli-wheel] Up to date: %s\n' "${existing_whl}"
  exit 0
fi

openfoam_safe_rm "${STAGING_DIR}"
openfoam_safe_rm "${CLI_BUILD_DIR}"
openfoam_safe_rm "${CLI_SRC}/build"
mkdir -p "${STAGING_DIR}/openfoam" "${STAGING_DIR}/completions/bash" "${CLI_BUILD_DIR}"

cp "${CLI_SRC}/openfoam/"*.py "${STAGING_DIR}/openfoam/"
cp "${CLI_SRC}/completions/bash/openfoam" "${STAGING_DIR}/completions/bash/openfoam"
cp "${CLI_SRC}/pyproject.toml" "${STAGING_DIR}/"
cp "${CLI_SRC}/setup.py" "${STAGING_DIR}/"
cat >"${STAGING_DIR}/setup.cfg" <<EOF
[build]
build-base=${CLI_BUILD_DIR}
EOF
sed_inplace -E "s/^__version__ = \".*\"/__version__ = \"${PKG_VERSION}\"/" \
  "${STAGING_DIR}/openfoam/__init__.py"
sed_inplace -E "s/^version = \".*\"/version = \"${PKG_VERSION}\"/" \
  "${STAGING_DIR}/pyproject.toml"

for script in openfoam.sh prefix.sh native.sh docker_run.sh shell_prompt.sh \
  shell_bashrc.sh _openfoam completion.bash completion.zsh rewrite_openfoam_paths.sh manifest.sh; do
  src="${CLI_SRC}/openfoam/${script}"
  [[ "${script}" == rewrite_openfoam_paths.sh ]] && src="${ROOT}/docker/rewrite_openfoam_paths.sh"
  cp "${src}" "${STAGING_DIR}/openfoam/${script}"
  chmod +x "${STAGING_DIR}/openfoam/${script}"
done

# shellcheck source=../cli/openfoam/manifest.sh
source "${ROOT}/cli/openfoam/manifest.sh"
write_cli_manifest "${STAGING_DIR}/openfoam/manifest.json" "wheel" 0 "${PKG_VERSION}"

rm -f "${WHEEL_DIR}"/openfoam_cli-*.whl "${WHEEL_DIR}"/openfoam-*.whl 2>/dev/null || true

wheel_pip_status=0
(
  cd "${STAGING_DIR}"
  for path in openfoam.egg-info dist; do
    openfoam_safe_rm "${path}"
  done
  if ! "${BUILD_PY}" -m pip wheel . -w "${WHEEL_DIR}" --no-cache-dir \
    --config-settings=--build-option=--keep-temp; then
    wheel_pip_status=$?
    whl="$(ls -t "${WHEEL_DIR}"/openfoam_cli-*.whl 2>/dev/null | head -1 || true)"
    if [[ -z "${whl}" ]]; then
      exit "${wheel_pip_status}"
    fi
    echo "[cli-wheel] pip exited ${wheel_pip_status} during temp cleanup; wheel OK: ${whl}" >&2
  fi
) || exit $?

openfoam_safe_rm "${STAGING_DIR}"
openfoam_safe_rm "${CLI_BUILD_DIR}"
printf '%s\n' "${PKG_VERSION}" >"${STAMP}"
printf '[cli-wheel] -> %s/openfoam_cli-*.whl\n' "${WHEEL_DIR}"
