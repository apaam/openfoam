#!/usr/bin/env bash
# Read/write phynexis-foam CLI manifest.json (schema 1).

set -euo pipefail

CLI_MANIFEST_NAME="manifest.json"
DEFAULT_PREFIX_ARCHIVE_NAME="phynexis-foam-prefix.tar.gz"

_openfoam_python() {
  printf '%s' "${OPENFOAM_PYTHON:-python3}"
}

write_cli_manifest() {
  local path="$1"
  local channel="$2"
  local has_archive="$3"
  local version="$4"
  local archive="${5:-${DEFAULT_PREFIX_ARCHIVE_NAME}}"
  "$(_openfoam_python)" - "${path}" "${channel}" "${has_archive}" "${version}" "${archive}" <<'PY'
import json, pathlib, sys
path, channel, has_archive, version, archive = sys.argv[1:6]
data = {
    "schema": 1,
    "channel": channel,
    "has_prefix_archive": has_archive == "1",
    "version": version,
}
if data["has_prefix_archive"]:
    data["prefix_archive"] = archive
pathlib.Path(path).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

read_cli_manifest() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    return 1
  fi
  "$(_openfoam_python)" - "${path}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in ("schema", "channel", "has_prefix_archive", "prefix_archive", "version"):
    value = data.get(key, "")
    if isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{key}={value}")
PY
}

load_cli_manifest() {
  local pkg_dir="$1"
  local line key value
  CLI_MANIFEST_SCHEMA=""
  CLI_MANIFEST_CHANNEL=""
  CLI_MANIFEST_HAS_PREFIX_ARCHIVE=""
  CLI_MANIFEST_PREFIX_ARCHIVE=""
  CLI_MANIFEST_VERSION=""
  if [[ ! -f "${pkg_dir}/${CLI_MANIFEST_NAME}" ]]; then
    return 1
  fi
  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    case "${key}" in
    schema) CLI_MANIFEST_SCHEMA="${value}" ;;
    channel) CLI_MANIFEST_CHANNEL="${value}" ;;
    has_prefix_archive) CLI_MANIFEST_HAS_PREFIX_ARCHIVE="${value}" ;;
    prefix_archive) CLI_MANIFEST_PREFIX_ARCHIVE="${value}" ;;
    version) CLI_MANIFEST_VERSION="${value}" ;;
    esac
  done < <(read_cli_manifest "${pkg_dir}/${CLI_MANIFEST_NAME}")
  return 0
}
