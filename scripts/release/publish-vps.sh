#!/usr/bin/env bash
# Publish OpenFOAM release artifacts to the VPS download service (dufs, port 8088).
#
# Reads server settings from ~/.xiaohe/agent/config.json (same as xiaohe-agent):
#   settings.vps_ssh      ssh alias, default: ts-vps
#   settings.vps_dir      remote download dir, default: /srv/downloads/openfoam
#   settings.vps_baseurl  public download base
#
# Renders install.sh from install.sh.in (substituting base URL + version),
# then rsyncs the tarball, wheel and install.sh to the VPS.
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

# --- read a settings key with a default ---
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

SSH_HOST="$(cfg vps_ssh ts-vps)"
REMOTE_DIR="$(cfg vps_dir /srv/downloads/openfoam)"
BASEURL="$(cfg vps_baseurl http://1.14.226.205:8088/openfoam)"

# --- version ---
VERSION="${OPENFOAM_VERSION:-v2412}"
info "Server : ${SSH_HOST}:${REMOTE_DIR}"
info "BaseURL: ${BASEURL}"
info "Version: ${VERSION}"

# --- find dist artifacts ---
DIST_NATIVE="${BUILD_ROOT:-build}/dist-native"
PACK=$(ls "$DIST_NATIVE"/phynexis-foam-*-*.tar.gz 2>/dev/null | head -1)
WHEEL=$(ls "$DIST_NATIVE"/phynexis_foam-*.whl 2>/dev/null | head -1)

if [[ -z "$PACK" || -z "$WHEEL" ]]; then
    die "Missing dist artifacts. Run 'make dist-native' first."
fi
info "Pack:  $(basename "$PACK")"
info "Wheel: $(basename "$WHEEL")"

# --- render install.sh ---
render() {
    local in="$1" out="$2"
    [[ -f "$in" ]] || die "Template missing: $in"
    sed -e "s#@BASEURL@#${BASEURL}#g" -e "s#@VERSION@#${VERSION}#g" "$in" > "$out"
}
TMP_INSTALL="$(mktemp -t of-install.XXXXXX.sh)"
trap 'rm -f "$TMP_INSTALL"' EXIT
info "Rendering install.sh ..."
render "$REL/install.sh.in" "$TMP_INSTALL"
chmod +x "$TMP_INSTALL"

# --- upload ---
info "Ensuring remote dir exists..."
ssh "$SSH_HOST" "mkdir -p '${REMOTE_DIR}'" || die "SSH failed. Check tailnet is up."

info "Uploading artifacts → ${SSH_HOST}:${REMOTE_DIR}/ ..."
rsync -avz --human-readable "$TMP_INSTALL" "${SSH_HOST}:${REMOTE_DIR}/install.sh"
rsync -avz --human-readable "$PACK"    "${SSH_HOST}:${REMOTE_DIR}/$(basename "$PACK")"
rsync -avz --human-readable "$WHEEL"   "${SSH_HOST}:${REMOTE_DIR}/$(basename "$WHEEL")"

echo ""
info "Published. Install with:"
echo ""
echo "    read -p 'Account: ' u && curl -u \"\$u\" -fsSL ${BASEURL}/install.sh | bash"
echo ""
