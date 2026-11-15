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
import time
import urllib.request

url = sys.argv[1]
last = None
for attempt in range(1, 6):
    try:
        with urllib.request.urlopen(url, timeout=120) as resp, open("pack.tar.gz", "wb") as out:
            expected = int(resp.headers.get("Content-Length") or 0)
            got = 0
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                got += len(chunk)
        if expected and got != expected:
            raise OSError(f"short read {got}/{expected}")
        break
    except Exception as exc:  # network flake: retry with a fresh connection
        last = exc
        print(f"[smoke] download attempt {attempt} failed: {exc}", file=sys.stderr)
        time.sleep(5)
else:
    raise SystemExit(f"download failed after retries: {last}")
PY

mkdir -p opt
tar -xzf pack.tar.gz -C opt
src="${work}/opt"
[[ -f "${src}/etc/bashrc" ]] || src="${work}/opt/openfoam"
[[ -f "${src}/etc/bashrc" ]] || { echo "[smoke] pack lacks etc/bashrc" >&2; exit 1; }

bash -c "set +e
  source '${src}/etc/bashrc' >/dev/null 2>&1
  set -e
  cp -r \"\$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity\" .
  cd cavity
  blockMesh >/dev/null
  icoFoam >/dev/null
  test -f 0.5/U"
echo "[smoke] cavity OK"
