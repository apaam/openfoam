#!/usr/bin/env bash
# Pack-time gate: fail native pack before tar/docker if bundled runtime is incomplete.
# Usage: verify_openfoam_pack.sh <product-prefix>
set -euo pipefail

STAGE="${1:?product prefix required}"
OF="${STAGE}/openfoam"
RUNTIME_DIR="${OF}/lib"
missing=0

fail() {
  echo "[verify_openfoam_pack] $*" >&2
  missing=1
}

if [[ ! -f "${STAGE}/etc/bashrc" ]]; then
  fail "Missing ${STAGE}/etc/bashrc"
  exit 1
fi

if [[ ! -f "${OF}/etc/bashrc" ]]; then
  fail "Missing openfoam/etc/bashrc (upstream)"
  exit 1
fi

if ! grep -qF 'openfoam/etc/bashrc' "${STAGE}/etc/bashrc"; then
  fail "etc/bashrc does not source openfoam/etc/bashrc"
fi

# Product root: wrapper etc/ + CLI; OF tree only under openfoam/.
for _of in platforms src applications wmake tutorials META-INFO; do
  if [[ -e "${STAGE}/${_of}" ]]; then
    fail "OpenFOAM path at product root: ${_of}/ (must be under openfoam/)"
  fi
done
if [[ -d "${STAGE}/etc/config.sh" ]]; then
  fail "product etc/ must be the dist wrapper only (found etc/config.sh)"
fi
if [[ -e "${STAGE}/lib" ]]; then
  fail "lib/ at product root (bundled runtime belongs under openfoam/lib/)"
fi
unset _of

# Locate a primary solver binary.
blockmesh=""
while IFS= read -r -d '' f; do
  blockmesh="${f}"
  break
done < <(find "${OF}/platforms" -type f -name blockMesh -print0 2>/dev/null || true)

if [[ -z "${blockmesh}" ]]; then
  fail "blockMesh not found under openfoam/platforms/"
fi

if [[ ! -f "${RUNTIME_DIR}/.bundle-stamp" ]]; then
  echo "[verify_openfoam_pack] No openfoam/lib/.bundle-stamp (OPENFOAM_BUNDLE_RUNTIME off?); static OF checks only"
  if ((missing != 0)); then
    exit 1
  fi
  echo "[verify_openfoam_pack] OK (no bundle): ${STAGE}"
  exit 0
fi

# --- bundled tree ---
shopt -s nullglob
mpi_libs=("${RUNTIME_DIR}"/libmpi.so* "${RUNTIME_DIR}"/libmpi*.dylib)
shopt -u nullglob
if ((${#mpi_libs[@]} == 0)); then
  fail "openfoam/lib/ has no libmpi (portable MPI expected)"
fi

if [[ ! -x "${RUNTIME_DIR}/mpi-bin/mpirun" && ! -x "${RUNTIME_DIR}/bin/mpirun" ]]; then
  fail "bundled mpirun missing (mpi-bin/ or bin/)"
fi

# Reject dangling Cellar-style links; require at least one OPAL help text
# (name varies across OMPI 4 orterun / OMPI 5 mpirun / vendor builds).
if [[ -L "${RUNTIME_DIR}/share/openmpi" && ! -e "${RUNTIME_DIR}/share/openmpi" ]]; then
  fail "openfoam/lib/share/openmpi is a dangling symlink (need deref copy)"
elif [[ -d "${RUNTIME_DIR}/share/openmpi" ]]; then
  _help_any="$(
    find "${RUNTIME_DIR}/share/openmpi" -maxdepth 1 -type f -name 'help-*.txt' \
      -print -quit 2>/dev/null || true
  )"
  if [[ -z "${_help_any}" ]]; then
    fail "openfoam/lib/share/openmpi has no help-*.txt (incomplete OPAL datadir)"
  fi
  unset _help_any
fi

# OpenMPI 5: mpirun execs prterun from the same bin dir.
if [[ -x "${RUNTIME_DIR}/mpi-bin/.real/mpirun" || -x "${RUNTIME_DIR}/mpi-bin/mpirun" ]]; then
  if [[ ! -x "${RUNTIME_DIR}/mpi-bin/prterun" && ! -x "${RUNTIME_DIR}/mpi-bin/.real/prterun" ]]; then
    # Only required when the real mpirun binary mentions prterun (OMPI 5+).
    _mpirun_bin="${RUNTIME_DIR}/mpi-bin/.real/mpirun"
    [[ -x "${_mpirun_bin}" ]] || _mpirun_bin="${RUNTIME_DIR}/mpi-bin/mpirun"
    if strings "${_mpirun_bin}" 2>/dev/null | grep -qF 'prterun-exec-failed'; then
      fail "OpenMPI 5 mpirun present but bundled prterun missing"
    fi
    unset _mpirun_bin
  fi
fi

pmix_plugins="$(
  find "${RUNTIME_DIR}/openmpi" \( -name 'mca_pmix*.so' -o -name 'mca_pmix*.dylib' \) \
    -type f 2>/dev/null | head -1 || true
)"
if [[ -n "${pmix_plugins}" ]]; then
  shopt -s nullglob
  pmix_libs=("${RUNTIME_DIR}"/libpmix.so* "${RUNTIME_DIR}"/libpmix*.dylib)
  shopt -u nullglob
  if ((${#pmix_libs[@]} == 0)); then
    fail "MCA pmix plugins present but libpmix.so* not in openfoam/lib/"
  fi
fi

# Unresolved deps for key ELF objects (relative to bundled + FOAM lib dirs).
check_ldd() {
  local bin="$1"
  local label="$2"
  local foam_lib=""
  foam_lib="$(dirname "$(dirname "${blockmesh}")")/lib"
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    fail "Unresolved dep for ${label}: ${line}"
  done < <(
    LD_LIBRARY_PATH="${RUNTIME_DIR}:${foam_lib}:${foam_lib}/sys-openmpi:${LD_LIBRARY_PATH:-}" \
      ldd "${bin}" 2>/dev/null | grep "not found" || true
  )
}

if command -v ldd >/dev/null 2>&1 && [[ -n "${blockmesh}" ]]; then
  check_ldd "${blockmesh}" "blockMesh"
  if [[ -n "${pmix_plugins}" ]]; then
    check_ldd "${pmix_plugins}" "$(basename "${pmix_plugins}")"
  fi
fi

# Smoke: source product etc/bashrc then run tools.
smoke_out="$(
  cd "${STAGE}" && env -i \
    HOME="${HOME:-/tmp}" \
    USER="${USER:-openfoam}" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash --noprofile --norc -c '
      set +eu
      set --
      # shellcheck disable=SC1091
      source "'"${STAGE}"'/etc/bashrc" || exit 10
      command -v blockMesh >/dev/null || exit 11
      blockMesh -help >/dev/null || exit 12
      if command -v mpirun >/dev/null; then
        mpirun --version >/dev/null || exit 13
      fi
      exit 0
    ' 2>&1
)" || smoke_rc=$?
smoke_rc="${smoke_rc:-0}"
if ((smoke_rc != 0)); then
  fail "Smoke source etc/bashrc failed (rc=${smoke_rc})"
  printf '%s\n' "${smoke_out}" | tail -40 >&2
fi

if ((missing != 0)); then
  echo "[verify_openfoam_pack] FAILED: ${STAGE}" >&2
  exit 1
fi

echo "[verify_openfoam_pack] OK: ${STAGE}"
