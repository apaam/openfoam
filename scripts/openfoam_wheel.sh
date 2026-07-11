#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/load_make_config.sh"
# shellcheck source=openfoam_install_paths.sh
source "${ROOT}/scripts/openfoam_install_paths.sh"

_bundle_override="${OPENFOAM_BUNDLE_RUNTIME+x}"
_saved_bundle="${OPENFOAM_BUNDLE_RUNTIME-}"
load_make_config "${ROOT}"
if [[ -n "${_bundle_override}" ]]; then
  export OPENFOAM_BUNDLE_RUNTIME="${_saved_bundle}"
else
  export OPENFOAM_BUNDLE_RUNTIME="${OPENFOAM_BUNDLE_RUNTIME:-0}"
fi

# 1 = native install tree + CLI (make wheel); 0 = CLI only (make cli)
INCLUDE_NATIVE="${INCLUDE_NATIVE:-1}"

OPENFOAM_BUILD="${OPENFOAM_BUILD:-${ROOT}/build/openfoam}"
OPENFOAM_STAGE="${OPENFOAM_STAGE:-${ROOT}/build/stage/openfoam}"
WHEELHOUSE_DIR="${WHEEL_OUT:-${OPENFOAM_WHEEL_DIR:-${BUILD_WHEEL_DIR:-build/wheel}}}"
if [[ "${INCLUDE_NATIVE}" == "0" ]]; then
  WHEELHOUSE_DIR="${WHEEL_OUT:-${DOCKER_DIST_DIR:-build/docker-dist}}"
fi
case "${WHEELHOUSE_DIR}" in
/*) ;;
*) WHEELHOUSE_DIR="${ROOT}/${WHEELHOUSE_DIR}" ;;
esac
case "${OPENFOAM_STAGE}" in
/*) ;;
*) OPENFOAM_STAGE="${ROOT}/${OPENFOAM_STAGE}" ;;
esac

CLI_SRC="${ROOT}/cli"
STAGING_DIR="${ROOT}/build/stage/wheel"
BUILD_PY="${BUILD_PY:-python3}"
NATIVE_PREFIX="${STAGING_DIR}/openfoam/prefix"
STAGE_STAMP="${OPENFOAM_STAGE}/.pack-stamp"

if [[ "${INCLUDE_NATIVE}" == "1" ]]; then
  PKG_VERSION="${OPENFOAM_VERSION:-v2412}"
  PKG_VERSION="${PKG_VERSION#v}"
else
  PKG_VERSION="${DOCKER_UBUNTU_VERSION:-24.04}"
fi

sed_inplace() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

wheel_has_native_prefix() {
  local whl="$1"
  unzip -l "${whl}" 2>/dev/null | grep -q 'openfoam/prefix/etc/bashrc'
}

write_native_manifest() {
  cat >"${STAGING_DIR}/MANIFEST.in" <<'EOF'
graft openfoam/prefix
recursive-include openfoam *.sh *.bash *.zsh *.py
EOF
}

write_native_setup_py() {
  cat >"${STAGING_DIR}/setup.py" <<'PY'
import setuptools

setuptools.setup(
  name="openfoam",
  version="PKG_VERSION_PLACEHOLDER",
  description="OpenFOAM install and command-line tools",
  python_requires=">=3.7",
  packages=["openfoam"],
  include_package_data=True,
  package_data={
    "openfoam": [
      "*.sh",
      "completion.bash",
      "completion.zsh",
    ],
  },
  entry_points={
    "console_scripts": [
      "openfoam=openfoam.cli:main",
    ],
  },
)
PY
  sed_inplace "s/PKG_VERSION_PLACEHOLDER/${PKG_VERSION}/" "${STAGING_DIR}/setup.py"
}

mkdir -p "${WHEELHOUSE_DIR}"
existing_whl="$(ls -t "${WHEELHOUSE_DIR}"/openfoam-*.whl 2>/dev/null | head -1 || true)"
if [[ "${INCLUDE_NATIVE}" == "1" && -n "${existing_whl}" && -f "${STAGE_STAMP}" \
  && "${existing_whl}" -nt "${STAGE_STAMP}" ]] \
  && openfoam_pack_stamp_matches "${STAGE_STAMP}" "${OPENFOAM_BUNDLE_RUNTIME}" \
  && wheel_has_native_prefix "${existing_whl}"; then
  printf '[openfoam-wheel] Up to date: %s\n' "${existing_whl}"
  exit 0
fi

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/openfoam"

cp "${CLI_SRC}/openfoam/"*.py "${STAGING_DIR}/openfoam/"
sed_inplace -E "s/^__version__ = \".*\"/__version__ = \"${PKG_VERSION}\"/" \
  "${STAGING_DIR}/openfoam/__init__.py"

for script in openfoam.sh prefix.sh native.sh docker_run.sh shell_prompt.sh \
  shell_bashrc.sh completion.bash completion.zsh rewrite_openfoam_paths.sh; do
  src="${CLI_SRC}/openfoam/${script}"
  [[ "${script}" == rewrite_openfoam_paths.sh ]] && src="${ROOT}/docker/rewrite_openfoam_paths.sh"
  cp "${src}" "${STAGING_DIR}/openfoam/${script}"
  chmod +x "${STAGING_DIR}/openfoam/${script}"
done

if [[ "${INCLUDE_NATIVE}" == "1" ]]; then
  bash "${ROOT}/scripts/prepare_openfoam_pack_tree.sh"

  echo "[openfoam-wheel] Staging native install -> openfoam/prefix/"
  rm -rf "${NATIVE_PREFIX}"
  mkdir -p "${NATIVE_PREFIX}"
  openfoam_rsync_install_tree "${OPENFOAM_STAGE}" "${NATIVE_PREFIX}"

  write_native_manifest
  write_native_setup_py
else
  cp "${CLI_SRC}/pyproject.toml" "${STAGING_DIR}/"
  sed_inplace -E "s/^version = \".*\"/version = \"${PKG_VERSION}\"/" \
    "${STAGING_DIR}/pyproject.toml"
  sed_inplace '/openfoam-native.tar.gz/d' "${STAGING_DIR}/pyproject.toml"
fi

rm -f "${WHEELHOUSE_DIR}"/openfoam-*.whl 2>/dev/null || true

(
  cd "${STAGING_DIR}"
  "${BUILD_PY}" -m pip wheel . -w "${WHEELHOUSE_DIR}" --no-cache-dir
)

rm -rf "${STAGING_DIR}"
if [[ "${INCLUDE_NATIVE}" == "1" ]]; then
  printf '[openfoam-wheel] -> %s/openfoam-*.whl\n' "${WHEELHOUSE_DIR}"
else
  printf '[openfoam-cli-wheel] -> %s/openfoam-*.whl\n' "${WHEELHOUSE_DIR}"
fi
