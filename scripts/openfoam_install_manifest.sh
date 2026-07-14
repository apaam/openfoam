#!/usr/bin/env bash
# Install-prefix ownership manifest (.openfoam-manifest.json).
# Tracks top-level entries written by make install so clean-install only
# removes product-owned paths and leaves foreign siblings alone.
# shellcheck shell=bash

OPENFOAM_INSTALL_MANIFEST_NAME=".openfoam-manifest.json"

# Top-level names this product may own under INSTALL_PREFIX.
OPENFOAM_INSTALL_OWNED_TOP=(
  bin
  etc
  openfoam
  share
  .pack-stamp
  .pack-source-prefix
  "${OPENFOAM_INSTALL_MANIFEST_NAME}"
)

openfoam_install_manifest_path() {
  local prefix="${1:?prefix}"
  printf '%s/%s' "${prefix}" "${OPENFOAM_INSTALL_MANIFEST_NAME}"
}

# Print owned top-level basenames that currently exist under prefix.
openfoam_install_owned_existing() {
  local prefix="${1:?prefix}"
  local name
  for name in "${OPENFOAM_INSTALL_OWNED_TOP[@]}"; do
    if [[ -e "${prefix}/${name}" ]]; then
      printf '%s\n' "${name}"
    fi
  done
}

# Remove previously owned top-level entries under prefix.
# keep_openfoam=1 skips openfoam/ (incremental restage).
openfoam_clear_install_owned() {
  local prefix="${1:?prefix}"
  local keep_openfoam="${2:-0}"
  local manifest entry name

  [[ -d "${prefix}" ]] || return 0

  manifest="$(openfoam_install_manifest_path "${prefix}")"
  if [[ -f "${manifest}" ]]; then
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      case "${entry}" in
      */* | "" | "." | "..") continue ;;
      openfoam)
        [[ "${keep_openfoam}" == "1" ]] && continue
        ;;
      esac
      openfoam_safe_rm "${prefix}/${entry}"
    done < <(openfoam_read_install_manifest_entries "${manifest}")
    return 0
  fi

  for name in "${OPENFOAM_INSTALL_OWNED_TOP[@]}"; do
    case "${name}" in
    openfoam)
      [[ "${keep_openfoam}" == "1" ]] && continue
      ;;
    esac
    openfoam_safe_rm "${prefix}/${name}"
  done
}

openfoam_write_install_manifest() {
  local prefix="${1:?prefix}"
  local bundle="${2:-0}"
  local version="${3:-}"
  local manifest entries_file count

  mkdir -p "${prefix}"
  manifest="$(openfoam_install_manifest_path "${prefix}")"
  entries_file="$(mktemp)"
  {
    openfoam_install_owned_existing "${prefix}"
    printf '%s\n' "${OPENFOAM_INSTALL_MANIFEST_NAME}"
  } | awk 'NF && !seen[$0]++' > "${entries_file}"
  count="$(wc -l < "${entries_file}" | tr -d ' ')"

  "${OPENFOAM_PYTHON:-python3}" - "${manifest}" "${bundle}" "${version}" \
    "${entries_file}" <<'PY'
import json, pathlib, sys
from datetime import datetime, timezone

manifest, bundle, version, entries_file = sys.argv[1:5]
entries = [
    line.strip()
    for line in pathlib.Path(entries_file).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
data = {
    "schema": 1,
    "kind": "install",
    "bundle": str(bundle),
    "version": str(version),
    "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "entries": entries,
}
pathlib.Path(manifest).write_text(
    json.dumps(data, indent=2) + "\n", encoding="utf-8"
)
PY
  rm -f "${entries_file}"
  echo "[install-manifest] Wrote ${manifest} (${count} entries)"
}

openfoam_read_install_manifest_entries() {
  local manifest="${1:?manifest}"
  "${OPENFOAM_PYTHON:-python3}" - "${manifest}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if data.get("schema") != 1:
    raise SystemExit(f"unsupported manifest schema: {data.get('schema')!r}")
for entry in data.get("entries") or []:
    if isinstance(entry, str) and entry and "/" not in entry and entry not in (".", ".."):
        print(entry)
PY
}

# Uninstall using manifest (or FORCE=1 known-name fallback). Never rm -rf prefix.
openfoam_uninstall_install_prefix() {
  local prefix="${1:?prefix}"
  local force="${2:-0}"
  local manifest entry remaining

  case "${prefix}" in
  "" | "." | ".." | "/" | *..*)
    echo "[uninstall] Refusing prefix='${prefix}'" >&2
    return 1
    ;;
  esac

  if [[ ! -e "${prefix}" ]]; then
    echo "[uninstall] Nothing to remove (${prefix})"
    return 0
  fi
  if [[ ! -d "${prefix}" ]]; then
    echo "[uninstall] Not a directory: ${prefix}" >&2
    return 1
  fi

  manifest="$(openfoam_install_manifest_path "${prefix}")"
  if [[ -f "${manifest}" ]]; then
    echo "[uninstall] Removing owned entries from ${prefix}"
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      case "${entry}" in
      */* | "." | "..") continue ;;
      esac
      openfoam_safe_rm "${prefix}/${entry}"
    done < <(openfoam_read_install_manifest_entries "${manifest}")
    # Manifest may already be gone if listed; ensure removed.
    openfoam_safe_rm "${manifest}"
  elif [[ "${force}" =~ ^(1|yes|true|on)$ ]]; then
    echo "[uninstall] No ${OPENFOAM_INSTALL_MANIFEST_NAME}; FORCE=1 removing known product names" >&2
    openfoam_clear_install_owned "${prefix}" 0
  else
    echo "[uninstall] Missing ${manifest}" >&2
    echo "[uninstall] Refusing to wipe ${prefix} (foreign files may be present)." >&2
    echo "[uninstall] Re-run make install to write a manifest, or FORCE=1 to remove known product names only." >&2
    return 1
  fi

  remaining="$(find "${prefix}" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1 || true)"
  if [[ -z "${remaining}" ]]; then
    rmdir "${prefix}" 2>/dev/null || openfoam_safe_rm "${prefix}"
    echo "[uninstall] Removed empty ${prefix}"
  else
    echo "[uninstall] Left ${prefix} (non-product files remain)"
  fi
}
