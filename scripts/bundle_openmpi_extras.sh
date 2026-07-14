#!/usr/bin/env bash
# Bundle OpenMPI MCA plugins (dlopen) and launcher binaries for parallel runs.
set -euo pipefail

STAGE="${1:?stage prefix required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="${STAGE}/lib"
MCA_SRC="${OPENMPI_MCA_SRC:-}"
MPI_BIN_DIR="${OPENMPI_MPI_BIN_DIR:-}"
SHARE_SRC_HINT="${OPENMPI_SHARE_SRC:-}"
FIX_RPATH="${ROOT}/scripts/bundle_fix_rpath.sh"
WRAP="${ROOT}/scripts/install_bundled_mpi_wrappers.sh"
platform="$(uname -s)"

if [[ ! -d "${RUNTIME_DIR}" ]]; then
  echo "[bundle_openmpi_extras] Missing ${RUNTIME_DIR}; skip" >&2
  exit 0
fi

has_bundled_mpi=false
shopt -s nullglob
for _lib in "${RUNTIME_DIR}"/libmpi.so* "${RUNTIME_DIR}"/libmpi*.dylib; do
  has_bundled_mpi=true
  break
done
shopt -u nullglob

if [[ "${has_bundled_mpi}" != true ]]; then
  echo "[bundle_openmpi_extras] No bundled libmpi; skip"
  exit 0
fi

if [[ -z "${MCA_SRC}" && -z "${MPI_BIN_DIR}" ]]; then
  echo "[bundle_openmpi_extras] No system OpenMPI layout found; skip"
  exit 0
fi

mca_has_plugins() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 1
  find "${dir}" \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) -print -quit 2>/dev/null | grep -q .
}

# Resolve brew/prefix symlinks then copy as real files (cp -a alone keeps
# absolute/relative Cellar links that break after relocation).
copy_tree_deref() {
  local src="$1"
  local dest="$2"
  local real_src
  [[ -e "${src}" ]] || return 1
  real_src="$(cd "${src}" && pwd -P)"
  mkdir -p "$(dirname "${dest}")"
  rm -rf "${dest}"
  cp -aL "${real_src}" "${dest}"
}

# Drop dangling external symlinks left by older packs / incomplete copies.
prune_broken_symlinks() {
  local root="$1"
  [[ -d "${root}" ]] || return 0
  find "${root}" -type l ! -exec test -e {} \; -print 2>/dev/null \
    | while IFS= read -r link; do
      echo "[bundle_openmpi_extras] Removing dangling symlink ${link}"
      rm -f "${link}"
    done
}

rpath_marker_to_runtime() {
  # $1 = directory containing the binary/plugin
  local from_dir="$1"
  local rel
  if rel="$(python3 -c "import os.path; print(os.path.relpath('${RUNTIME_DIR}', '${from_dir}'))" 2>/dev/null)"; then
    :
  elif rel="$(realpath --relative-to="${from_dir}" "${RUNTIME_DIR}" 2>/dev/null)"; then
    :
  else
    # Fallback: openmpi/lib/openmpi3 -> ../../..
    rel='../../..'
  fi
  case "${platform}" in
  Darwin) printf '@loader_path/%s' "${rel}" ;;
  *) printf '$ORIGIN/%s' "${rel}" ;;
  esac
}

case "${platform}" in
Darwin) launcher_marker='@executable_path/..' ;;
*) launcher_marker='$ORIGIN/..' ;;
esac

if [[ -n "${MCA_SRC}" ]] && mca_has_plugins "${MCA_SRC}"; then
  dest="${RUNTIME_DIR}/openmpi"
  echo "[bundle_openmpi_extras] MCA ${MCA_SRC} -> ${dest}"
  copy_tree_deref "${MCA_SRC}" "${dest}"

  mca_fixed=0
  mca_failed=0
  while IFS= read -r -d '' plugin; do
    chmod u+w "${plugin}" 2>/dev/null || true
    marker="$(rpath_marker_to_runtime "$(dirname "${plugin}")")"
    if FIX_RPATH_SEARCH_PATHS="${RUNTIME_DIR}:${MCA_SRC}:${LD_LIBRARY_PATH:-}" \
      "${FIX_RPATH}" "${plugin}" "${RUNTIME_DIR}" "${marker}" "${RUNTIME_DIR}" \
      >/dev/null; then
      mca_fixed=$((mca_fixed + 1))
    else
      mca_failed=$((mca_failed + 1))
      echo "[bundle_openmpi_extras] ERROR: fix_rpath failed for ${plugin##*/}" >&2
    fi
  done < <(
    find "${dest}" \( -name 'mca_*.so' -o -name 'mca_*.dylib' \) -type f -print0 2>/dev/null
  )
  if ((mca_fixed > 0)); then
    echo "[bundle_openmpi_extras] Fixed rpath/deps for ${mca_fixed} MCA plugin(s)"
  fi
  if ((mca_failed > 0)); then
    echo "[bundle_openmpi_extras] ${mca_failed} MCA plugin(s) failed fix_rpath" >&2
    exit 1
  fi

  # Pull libpmix (and friends) explicitly if MCA pmix was copied.
  if find "${dest}" \( -name 'mca_pmix*.so' -o -name 'mca_pmix*.dylib' \) -print -quit \
    2>/dev/null | grep -q .; then
    bash "${ROOT}/scripts/ensure_bundled_libpmix.sh" "${STAGE}"
    shopt -s nullglob
    pmix_libs=("${RUNTIME_DIR}"/libpmix.so* "${RUNTIME_DIR}"/libpmix*.dylib)
    shopt -u nullglob
    if ((${#pmix_libs[@]} == 0)); then
      echo "[bundle_openmpi_extras] ERROR: MCA pmix plugins present but libpmix not bundled" >&2
      exit 1
    fi
    echo "[bundle_openmpi_extras] libpmix present: $(basename "${pmix_libs[0]}")"
  fi
fi

# Help texts (OPAL_DATADIR / PRTE). Prefer discovery from the linked MPI tree.
share_src=""
if [[ -n "${SHARE_SRC_HINT}" && -d "${SHARE_SRC_HINT}" ]]; then
  share_src="${SHARE_SRC_HINT}"
elif [[ -n "${MPI_BIN_DIR}" ]]; then
  walk="${MPI_BIN_DIR}"
  for _ in 1 2 3 4 5 6; do
    walk="$(dirname "${walk}")"
    [[ "${walk}" == / ]] && break
    if [[ -d "${walk}/share/openmpi" ]]; then
      share_src="${walk}/share/openmpi"
      break
    fi
  done
fi
if [[ -z "${share_src}" && -n "${MCA_SRC}" ]]; then
  walk="${MCA_SRC}"
  for _ in 1 2 3 4 5 6; do
    walk="$(dirname "${walk}")"
    [[ "${walk}" == / ]] && break
    if [[ -d "${walk}/share/openmpi" ]]; then
      share_src="${walk}/share/openmpi"
      break
    fi
  done
fi
if [[ -n "${share_src}" && -d "${share_src}" ]]; then
  share_dest="${RUNTIME_DIR}/share/openmpi"
  echo "[bundle_openmpi_extras] share ${share_src} -> ${share_dest}"
  copy_tree_deref "${share_src}" "${share_dest}"
  prune_broken_symlinks "${share_dest}"
  # OpenMPI 5 PRTE help texts live beside openmpi/ when present.
  prte_share_src="$(dirname "${share_src}")/prte"
  if [[ -d "${prte_share_src}" ]]; then
    prte_share_dest="${RUNTIME_DIR}/share/prte"
    echo "[bundle_openmpi_extras] share ${prte_share_src} -> ${prte_share_dest}"
    copy_tree_deref "${prte_share_src}" "${prte_share_dest}"
    prune_broken_symlinks "${prte_share_dest}"
  fi
elif [[ -n "${MPI_BIN_DIR}" || -n "${MCA_SRC}" ]]; then
  echo "[bundle_openmpi_extras] WARN: could not locate share/openmpi for bundled MPI" >&2
fi

if [[ -n "${MPI_BIN_DIR}" && -d "${MPI_BIN_DIR}" ]]; then
  mpi_bin_dest="${RUNTIME_DIR}/mpi-bin"
  mkdir -p "${mpi_bin_dest}"
  search_paths="${RUNTIME_DIR}:${mpi_bin_dest}"
  bundled=0
  # OMPI ≤4: orterun/orted; OMPI 5+: prterun/prted (mpirun execs prterun).
  for cmd in mpirun mpiexec orterun orted prterun prted prte prun; do
    src="${MPI_BIN_DIR}/${cmd}"
    [[ -e "${src}" ]] || continue
    dest="${mpi_bin_dest}/${cmd}"
    cp -fL "${src}" "${dest}"
    chmod u+w "${dest}" 2>/dev/null || true
    FIX_RPATH_SEARCH_PATHS="${search_paths}" \
      "${FIX_RPATH}" "${dest}" "${RUNTIME_DIR}" "${launcher_marker}" "${search_paths}"
    bundled=$((bundled + 1))
  done
  if ((bundled > 0)); then
    echo "[bundle_openmpi_extras] Bundled ${bundled} MPI launcher(s) -> ${mpi_bin_dest}/"
  fi
fi

if [[ -d "${RUNTIME_DIR}/mpi-bin" ]] && [[ ! -e "${RUNTIME_DIR}/bin" ]]; then
  ln -sfn mpi-bin "${RUNTIME_DIR}/bin"
fi
if [[ ! -e "${RUNTIME_DIR}/lib" ]]; then
  ln -sfn . "${RUNTIME_DIR}/lib"
fi

if [[ -d "${RUNTIME_DIR}/mpi-bin" ]]; then
  bash "${WRAP}" "${RUNTIME_DIR}"
fi

echo "[bundle_openmpi_extras] Done"
