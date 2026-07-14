#!/usr/bin/env bash
# Pack-time only: if bundled OpenMPI MCA includes pmix, copy libpmix into lib
# from the *build* host. Runtime Docker images must not call this — libpmix ships
# inside openfoam-native tar.
# Usage: ensure_bundled_libpmix.sh <stage-prefix>
set -euo pipefail

STAGE="${1:?stage prefix required}"
RUNTIME_DIR="${STAGE}/lib"

if [[ ! -d "${RUNTIME_DIR}" ]]; then
  exit 0
fi

if ! find "${RUNTIME_DIR}/openmpi" \( -name 'mca_pmix*.so' -o -name 'mca_pmix*.dylib' \) \
  -type f 2>/dev/null | grep -q .; then
  exit 0
fi

# Drop broken symlinks left by incomplete prior copies (cp refuses to write through them).
shopt -s nullglob
for link in "${RUNTIME_DIR}"/libpmix.so* "${RUNTIME_DIR}"/libpmix*.dylib; do
  if [[ -L "${link}" && ! -e "${link}" ]]; then
    echo "[ensure_bundled_libpmix] Removing dangling symlink ${link}"
    rm -f "${link}"
  fi
done

has_real=false
for f in "${RUNTIME_DIR}"/libpmix.so* "${RUNTIME_DIR}"/libpmix*.dylib; do
  if [[ -e "${f}" ]]; then
    has_real=true
    break
  fi
done
shopt -u nullglob

if [[ "${has_real}" == true ]]; then
  exit 0
fi

# Search build host for libpmix.
candidates=()
while IFS= read -r p; do
  [[ -n "${p}" ]] && candidates+=("${p}")
done < <(
  {
    ldconfig -p 2>/dev/null | awk '/libpmix\.so/{print $NF}'
    ls /usr/lib/*/libpmix.so* /lib/*/libpmix.so* \
      /usr/lib/libpmix.so* /lib/libpmix.so* 2>/dev/null
  } | awk 'NF && !seen[$0]++'
)

if ((${#candidates[@]} == 0)); then
  echo "[ensure_bundled_libpmix] MCA pmix present but libpmix not found on build host" >&2
  echo "[ensure_bundled_libpmix] Fix the OpenMPI build stack (libpmix) and re-run native pack" >&2
  exit 1
fi

copied=0
for src in "${candidates[@]}"; do
  [[ -e "${src}" ]] || continue
  # Resolve to a real file so we never plant dangling soname links.
  real="${src}"
  if [[ -L "${src}" ]]; then
    real="$(readlink -f "${src}" 2>/dev/null || true)"
    [[ -n "${real}" && -f "${real}" ]] || real="$(realpath "${src}" 2>/dev/null || true)"
  fi
  [[ -f "${real}" ]] || continue

  dest_real="${RUNTIME_DIR}/$(basename "${real}")"
  rm -f "${dest_real}"
  cp -a "${real}" "${dest_real}"

  # Recreate soname / short-name symlinks next to the real file when needed.
  base="$(basename "${src}")"
  if [[ "${base}" != "$(basename "${real}")" ]]; then
    dest_link="${RUNTIME_DIR}/${base}"
    rm -f "${dest_link}"
    ln -s "$(basename "${real}")" "${dest_link}"
  fi
  # Common libpmix.so.2 -> libpmix.so.2.x.y
  if [[ "$(basename "${real}")" =~ ^libpmix\.so\.[0-9]+\. ]]; then
    major="$(basename "${real}" | sed -E 's/^(libpmix\.so\.[0-9]+).*/\1/')"
    if [[ ! -e "${RUNTIME_DIR}/${major}" ]]; then
      ln -s "$(basename "${real}")" "${RUNTIME_DIR}/${major}"
    fi
  fi
  copied=$((copied + 1))
done

if ((copied == 0)); then
  echo "[ensure_bundled_libpmix] Failed to copy libpmix into ${RUNTIME_DIR}" >&2
  exit 1
fi
echo "[ensure_bundled_libpmix] Copied libpmix into ${RUNTIME_DIR} (${copied} path(s))"
