#!/usr/bin/env bash
# Publish an OpenFOAM release pack to the dufs download service.
#
# Layout (docs/ci-release.md, phynexis-ops references/openfoam.md):
#   /srv/downloads/openfoam/<ver>/openfoam-native-2412-linux-x86_64.tar.gz
# The version directory is what CI pins (OPENFOAM_RELEASE_TAG) and what the
# download page links to, so it is published atomically per version and old
# versions are pruned to KEEP_VERSIONS (default 3).
#
# Usage: OPENFOAM_RELEASE_TAG=v2412.6 bash scripts/release/publish-vps.sh
#
# Settings are read from ~/.xiaohe/agent/settings.json or
# ~/.xiaohe/agent/config.json (settings.*); the defaults below are the current
# production values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[publish]${NC} $*"; }
warn() { echo -e "${YELLOW}[publish]${NC} $*"; }
die()  { echo -e "${RED}[publish]${NC} $*" >&2; exit 1; }

CONFIG="$HOME/.xiaohe/agent/config.json"
SETTINGS="$HOME/.xiaohe/agent/settings.json"
REL="$ROOT/scripts/release"

cfg() {
    python3 - "$SETTINGS" "$CONFIG" "$1" "${2:-}" <<'PY'
import json, sys
settings_path, config_path, key, default = sys.argv[1:5]
def read(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}
val = read(settings_path).get(key, "")
if not val:
    val = (read(config_path).get("settings") or {}).get(key, "")
print(val or default)
PY
}

SSH_HOST="${OPENFOAM_VPS_SSH:-${XIAOHE_VPS_SSH:-$(cfg vps_ssh ts-xiaohe)}}"
# CI writes the VPS SSH config outside ~/.ssh (XIAOHE_SSH_HOME); honour it.
SSH_OPTS=()
SCP_OPTS=()
if [[ -n "${XIAOHE_SSH_HOME:-}" && -f "${XIAOHE_SSH_HOME}/config" ]]; then
  SSH_OPTS+=(-F "${XIAOHE_SSH_HOME}/config")
  SCP_OPTS+=(-F "${XIAOHE_SSH_HOME}/config")
fi
if [[ -n "${XIAOHE_VPS_SSH_PORT:-}" ]]; then
  SSH_OPTS+=(-p "${XIAOHE_VPS_SSH_PORT}")
  SCP_OPTS+=(-P "${XIAOHE_VPS_SSH_PORT}")
fi
REMOTE_DIR="$(cfg vps_dir /srv/downloads/openfoam)"
BASEURL="$(cfg vps_baseurl https://download.xiaohe.team/openfoam)"

VERSION="${OPENFOAM_RELEASE_TAG:-}"
[[ -n "$VERSION" ]] || die "Set OPENFOAM_RELEASE_TAG (e.g. v2412.6)"
[[ "$VERSION" =~ ^v[0-9] ]] || die "OPENFOAM_RELEASE_TAG must look like v2412.6 (got '$VERSION')"
KEEP_VERSIONS="${KEEP_VERSIONS:-3}"

info "Server  : ${SSH_HOST}:${REMOTE_DIR}/${VERSION}"
info "BaseURL : ${BASEURL}"
info "Keep    : ${KEEP_VERSIONS} version dirs"

# --- dist artifacts -------------------------------------------------------
shopt -s nullglob
DIST_NATIVE="${BUILD_ROOT:-build}/dist-native"
PACKS=("$DIST_NATIVE"/openfoam-native-*.tar.gz "$DIST_NATIVE"/phynexis-foam-*.tar.gz)
WHEELS=("$DIST_NATIVE"/phynexis_foam-*.whl)
[[ ${#PACKS[@]} -gt 0 ]] || die "Missing dist pack. Run 'make dist-native' first."
PACK="$(ls -1t "${PACKS[@]}" | head -1)"
WHEEL=""
[[ ${#WHEELS[@]} -gt 0 ]] && WHEEL="$(ls -1t "${WHEELS[@]}" | head -1)"
# Asset name follows the PACK, not the host: the upload job may run on macOS
# while the pack is a Linux build. The Linux pack keeps the historical
# "-linux-x86_64" name the phynexis CI pattern-matches on.
if [[ -n "${OPENFOAM_ASSET_OS_ARCH:-}" ]]; then
  OS_ARCH="${OPENFOAM_ASSET_OS_ARCH}"
else
  case "$(basename "$PACK")" in
    *-linux-amd64.tar.gz | *-linux-x86_64.tar.gz) OS_ARCH=linux-x86_64 ;;
    *-linux-arm64.tar.gz)                         OS_ARCH=linux-arm64 ;;
    *-darwin-arm64.tar.gz)                        OS_ARCH=darwin-arm64 ;;
    *) OS_ARCH="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)" ;;
  esac
fi
ASSET="openfoam-native-2412-${OS_ARCH}.tar.gz"
info "Pack  : $(basename "$PACK") → ${ASSET}"
[[ -n "$WHEEL" ]] && info "Wheel : $(basename "$WHEEL")"

# --- gate: glibc floor (32-bit-safe symbol scan) --------------------------
# Policy: published packs must not reference a GLIBC symbol newer than 2.35;
# a 24.04 build silently ships __isoc23_*@GLIBC_2.38 and breaks every 22.04
# host (this is what bit the v2412.5 pack).
GLIBC_FLOOR="${GLIBC_FLOOR:-2.35}"
if [[ "${OS_ARCH}" == darwin-* ]]; then
  info "Darwin pack: skipping the GLIBC floor check (Mach-O)"
elif ! objdump -T /bin/true >/dev/null 2>&1; then
  info "host objdump cannot read ELF; the pack was gated in the build container"
else
info "Verifying glibc floor ≤ ${GLIBC_FLOOR} ..."
STAGE="$(mktemp -d -t of-verify.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
tar -xzf "$PACK" -C "$STAGE"
max="$(find "$STAGE" -name '*.so*' -type f -print0 \
        | xargs -0 -r objdump -T 2>/dev/null \
        | grep -oE 'GLIBC_2\.[0-9]+' | sort -V | tail -1 | cut -d_ -f2)"
[[ -n "$max" ]] || die "could not read GLIBC symbols from $PACK"
info "max GLIBC symbol: GLIBC_${max}"
if [[ "$(printf '%s\n%s\n' "$GLIBC_FLOOR" "$max" | sort -V | tail -1)" != "$GLIBC_FLOOR" ]]; then
    die "pack references GLIBC_${max} > ${GLIBC_FLOOR}: rebuild on the Ubuntu 22.04 baseline"
fi
fi

# --- upload ---------------------------------------------------------------
info "Uploading → ${SSH_HOST}:${REMOTE_DIR}/${VERSION}/ ..."
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "sudo mkdir -p '${REMOTE_DIR}/${VERSION}' && sudo chown -R \$(id -un): '${REMOTE_DIR}'"
scp "${SCP_OPTS[@]}" -q "$PACK" "${SSH_HOST}:/tmp/$(basename "$ASSET")"
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "sudo mv '/tmp/$(basename "$ASSET")' '${REMOTE_DIR}/${VERSION}/${ASSET}' \
  && sudo chmod -R a+rX '${REMOTE_DIR}/${VERSION}'"
if [[ -n "$WHEEL" ]]; then
    scp "${SCP_OPTS[@]}" -q "$WHEEL" "${SSH_HOST}:/tmp/$(basename "$WHEEL")"
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "sudo mv '/tmp/$(basename "$WHEEL")' '${REMOTE_DIR}/${VERSION}/$(basename "$WHEEL")' \
      && sudo chmod a+r '${REMOTE_DIR}/${VERSION}/$(basename "$WHEEL")'"
fi

# --- render install.sh at the channel root --------------------------------
if [[ -f "$REL/install.sh.in" ]]; then
    TMP_INSTALL="$(mktemp -t of-install.XXXXXX.sh)"
    sed -e "s#@BASEURL@#${BASEURL}#g" -e "s#@VERSION@#${VERSION}#g" "$REL/install.sh.in" > "$TMP_INSTALL"
    chmod +x "$TMP_INSTALL"
    scp "${SCP_OPTS[@]}" -q "$TMP_INSTALL" "${SSH_HOST}:/tmp/install.sh"
    ssh "${SSH_OPTS[@]}" "$SSH_HOST" "sudo mv /tmp/install.sh '${REMOTE_DIR}/install.sh' && sudo chmod a+rX '${REMOTE_DIR}/install.sh'"
    rm -f "$TMP_INSTALL"
    info "install.sh rendered for ${VERSION}"
fi

# --- prune (keep newest KEEP_VERSIONS) ------------------------------------
info "Pruning old version dirs (keep ${KEEP_VERSIONS}) ..."
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "sudo bash -s -- '${REMOTE_DIR}' '${VERSION}' '${KEEP_VERSIONS}'" <<'REMOTE'
set -euo pipefail
DIR="$1"; CUR="$2"; KEEP="$3"
cd "$DIR"
mapfile -t all < <(ls -1d v[0-9]* 2>/dev/null | sort -V)
n=${#all[@]}
if (( n > KEEP )); then
  for ((i=0; i<n-KEEP; i++)); do
    old="${all[$i]}"
    [[ "$old" == "$CUR" ]] && continue
    echo "  prune $old"
    rm -rf "$old"
  done
fi
ls -1d v[0-9]* 2>/dev/null | sort -V | sed 's/^/  keep /'
REMOTE

info "Published ${VERSION}"
echo "    ${BASEURL}/${VERSION}/${ASSET}"
