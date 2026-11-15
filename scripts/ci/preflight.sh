#!/usr/bin/env bash
# Runs INSIDE the ubuntu 22.04 build image (see docker/preflight.sh).
# Fail fast on the OpenFOAM release environment contract.
set -euo pipefail

fail=0
note() { printf '%s\n' "$*"; }
bad() { printf 'PREFLIGHT FAIL: %s\n' "$*" >&2; fail=1; }

note "[preflight] $(uname -s) $(uname -m), $(. /etc/os-release && echo "$PRETTY_NAME")"
if ! . /etc/os-release || [[ "${VERSION_ID:-}" != "22.04" ]]; then
  bad "build image must be Ubuntu 22.04 (got ${VERSION_ID:-unknown})"
fi

for tool in gcc g++ make python3 objdump tar; do
  command -v "${tool}" >/dev/null || bad "${tool} missing"
done

# objdump must be able to read ELF symbol tables (the glibc gate uses it).
if ! objdump -T /lib/x86_64-linux-gnu/libc.so.6 >/dev/null 2>&1; then
  bad "objdump cannot read ELF symbols"
fi

avail="$(df -P / | awk 'NR==2 {print $4}')"
((avail > 8 * 1024 * 1024)) || bad "less than 8 GiB free in the build tree"

if ((fail)); then
  exit 1
fi
note "[preflight] OK"
