#!/usr/bin/env bash
# Install self-locating wrappers around bundled OpenMPI launchers.
#
# Usage:
#   install_bundled_mpi_wrappers.sh <runtime-lib-dir>
#   install_bundled_mpi_wrappers.sh <stage-prefix>   # uses <stage>/lib
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?runtime lib dir or stage prefix required}"
ENV_SRC="${ROOT}/scripts/openfoam_mpi_env.sh"
if [[ ! -f "${ENV_SRC}" ]]; then
  ENV_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openfoam_mpi_env.sh"
fi

# Prefer direct mpi-bin: TARGET may already be the runtime lib dir, which also
# has lib -> . so TARGET/lib/mpi-bin would falsely match via that symlink.
if [[ -d "${TARGET}/mpi-bin" ]]; then
  RUNTIME_DIR="${TARGET}"
elif [[ -d "${TARGET}/lib/mpi-bin" ]]; then
  RUNTIME_DIR="${TARGET}/lib"
elif [[ -d "${TARGET}" ]]; then
  RUNTIME_DIR="${TARGET}"
else
  echo "[install_bundled_mpi_wrappers] Not a directory: ${TARGET}" >&2
  exit 1
fi

MPI_BIN="${RUNTIME_DIR}/mpi-bin"
if [[ ! -d "${MPI_BIN}" ]]; then
  echo "[install_bundled_mpi_wrappers] No ${MPI_BIN}; skip"
  exit 0
fi

if [[ ! -f "${ENV_SRC}" ]]; then
  echo "[install_bundled_mpi_wrappers] Missing ${ENV_SRC}" >&2
  exit 1
fi

mkdir -p "${MPI_BIN}/.real"
cp -f "${ENV_SRC}" "${MPI_BIN}/openfoam_mpi_env.sh"
chmod 755 "${MPI_BIN}/openfoam_mpi_env.sh"

is_our_wrapper() {
  local f="$1"
  [[ -f "${f}" ]] && head -n 8 "${f}" | grep -qF 'openfoam_mpi_env.sh'
}

wrapped=0
# OMPI ≤4: orterun/orted; OMPI 5+: prterun/prted (mpirun execs prterun).
for cmd in mpirun mpiexec orterun orted prterun prted prte prun; do
  src="${MPI_BIN}/${cmd}"
  [[ -e "${src}" ]] || continue
  real="${MPI_BIN}/.real/${cmd}"

  if is_our_wrapper "${src}"; then
    if [[ ! -x "${real}" ]]; then
      echo "[install_bundled_mpi_wrappers] Wrapper ${cmd} missing .real/${cmd}" >&2
      exit 1
    fi
    continue
  fi

  # Follow symlinks so .real holds a real ELF/Mach-O binary.
  cp -fL "${src}" "${real}"
  chmod u+w "${real}" 2>/dev/null || true
  chmod 755 "${real}" 2>/dev/null || true
  rm -f "${src}"

  cat >"${src}" <<EOF
#!/usr/bin/env bash
# OpenFOAM bundled OpenMPI launcher (relocatable).
set -euo pipefail
_MPI_BIN="\$(CDPATH= cd -- "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "\${_MPI_BIN}/openfoam_mpi_env.sh"
exec "\${_MPI_BIN}/.real/${cmd}" "\$@"
EOF
  chmod 755 "${src}"
  wrapped=$((wrapped + 1))
done

if [[ ! -e "${RUNTIME_DIR}/bin" ]]; then
  ln -sfn mpi-bin "${RUNTIME_DIR}/bin"
fi

echo "[install_bundled_mpi_wrappers] Installed wrappers (${wrapped} updated) under ${MPI_BIN}"
