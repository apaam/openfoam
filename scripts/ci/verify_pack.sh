#!/usr/bin/env bash
# Runs INSIDE the ubuntu 22.04 build image (see docker/verify_pack.sh).
# Gates the published pack: GLIBC floor, unresolved libraries, bashrc smoke.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

FLOOR="${GLIBC_FLOOR:-2.35}"
ROOT_DIR="${BUILD_ROOT:-docker-build}"
[ -d "${ROOT_DIR}/dist-native" ] || ROOT_DIR=docker-build
ROOT="${ROOT_DIR}/dist-native"
shopt -s nullglob
packs=("${ROOT}"/*.tar.gz)
shopt -u nullglob
((${#packs[@]})) || { echo "[verify] no pack in ${ROOT}" >&2; exit 1; }
tar="$(printf '%s\n' "${packs[@]}" | sort -V | tail -1)"
echo "[verify] $(basename "${tar}") (glibc <= ${FLOOR})"

stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
tar -xzf "${tar}" -C "${stage}"

max="$(find "${stage}" -name '*.so*' -type f -print0 \
  | xargs -0 -r objdump -T 2>/dev/null \
  | grep -oE 'GLIBC_2\.[0-9]+' | sort -V | tail -1 | cut -d_ -f2)"
[[ -n "${max}" ]] || { echo "[verify] cannot read GLIBC symbols" >&2; exit 1; }
echo "[verify] max GLIBC symbol: GLIBC_${max}"
if [[ "$(printf '%s\n%s\n' "${FLOOR}" "${max}" | sort -V | tail -1)" != "${FLOOR}" ]]; then
  echo "[verify] GLIBC_${max} > ${FLOOR}: rebuild on the 22.04 baseline" >&2
  exit 1
fi

bad=0
while IFS= read -r lib; do
  if ldd -r "${lib}" 2>&1 | grep -q "not found"; then
    echo "[verify] unresolved libs: ${lib}"
    ldd -r "${lib}" | grep "not found"
    bad=1
  fi
done < <(find "${stage}" -name '*.so*' -type f)
[[ "${bad}" -eq 0 ]] || exit 1

src="${stage}"
[[ -f "${src}/etc/bashrc" ]] || src="${stage}/openfoam"
[[ -f "${src}/etc/bashrc" ]] || { echo "[verify] pack lacks etc/bashrc" >&2; exit 1; }
bash -c "source '${src}/etc/bashrc' >/dev/null 2>&1; command -v wmake blockMesh icoFoam"
echo "[verify] OK"
