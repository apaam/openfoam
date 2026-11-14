#!/usr/bin/env bash
# Runs INSIDE the ubuntu 22.04 build image (see docker/install-smoke.sh).
# Downloads the published pack and runs the icoFoam cavity tutorial.
set -euo pipefail

tag="${RELEASE_TAG:?RELEASE_TAG required}"
base="${OPENFOAM_BASEURL:-https://download.xiaohe.team}"
asset="openfoam-native-2412-linux-x86_64.tar.gz"
url="${base%/}/openfoam/${tag}/${asset}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"

echo "[smoke] fetch ${url}"
python3 - "${url}" <<'PY'
import sys
import urllib.request

urllib.request.urlretrieve(sys.argv[1], "pack.tar.gz")
PY

mkdir -p opt
tar -xzf pack.tar.gz -C opt
src="${work}/opt"
[[ -f "${src}/etc/bashrc" ]] || src="${work}/opt/openfoam"
[[ -f "${src}/etc/bashrc" ]] || { echo "[smoke] pack lacks etc/bashrc" >&2; exit 1; }

bash -c "set -e
  source '${src}/etc/bashrc' >/dev/null
  cp -r \"\$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity\" .
  cd cavity
  blockMesh >/dev/null
  icoFoam >/dev/null
  test -f 0.5/U"
echo "[smoke] cavity OK"
