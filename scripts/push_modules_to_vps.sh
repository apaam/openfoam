#!/usr/bin/env bash
# Push the openfoam-source submodule mirror to ts-vps.
#
# Mirror: ts-vps:apaam/repo/modules/openfoam-source.git (bare). The local
# clone is shallow, so the mirror runs receive.shallowUpdate=true; besides
# --all/--tags, the recorded pin commit is pushed to refs/heads/__pin so the
# VPS can always fetch the exact submodule commit. The VPS checkout overrides
# submodule.openfoam-source.url to the mirror, avoiding gitlab.com entirely.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

DST="${TS_VPS_MODULE_BASE:-ts-vps:apaam/repo/modules}/openfoam-source.git"
MOD=openfoam-source

pin=$(git ls-tree HEAD "${MOD}" | awk '{print $3}')
echo "[push-modules] openfoam-source -> ${DST}"

if ! git -C "${MOD}" push "${DST}" --all; then
  echo "[push-modules] openfoam-source: branch push FAILED"
  exit 1
fi

refspecs=()
while IFS= read -r tag; do
  sha=$(git -C "${MOD}" rev-parse -q "refs/tags/${tag}^{commit}" 2>/dev/null) || continue
  if git -C "${MOD}" cat-file -e "${sha}" 2>/dev/null; then
    refspecs+=("refs/tags/${tag}:refs/tags/${tag}")
  fi
done < <(git -C "${MOD}" for-each-ref refs/tags --format='%(refname:strip=2)')
if ((${#refspecs[@]})); then
  git -C "${MOD}" push "${DST}" "${refspecs[@]}" \
    || echo "[push-modules] openfoam-source: some tags FAILED (non-fatal)"
fi

if ! git -C "${MOD}" push "${DST}" "${pin}:refs/heads/__pin"; then
  echo "[push-modules] openfoam-source: __pin push FAILED"
  exit 1
fi
echo "[push-modules] done. On the VPS, run: git submodule update --init"
