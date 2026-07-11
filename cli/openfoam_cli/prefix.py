"""Resolve native OpenFOAM install prefix (wheel layout)."""

from __future__ import annotations

import tarfile
from pathlib import Path
from typing import Optional

_PREFIX: Optional[Path] = None


def _package_dir() -> Path:
    return Path(__file__).resolve().parent


def _rewrite_installed_prefix(installed: Path) -> None:
    marker = installed / ".pack-source-prefix"
    if not marker.is_file():
        return
    old_prefix = marker.read_text(encoding="utf-8").strip()
    new_prefix = str(installed.resolve())
    if not old_prefix or old_prefix == new_prefix:
        return
    script = _package_dir() / "rewrite_openfoam_paths.sh"
    if not script.is_file():
        return
    import subprocess

    subprocess.run(
        ["bash", str(script), str(installed), old_prefix, new_prefix],
        check=True,
    )


def native_prefix() -> Path:
    global _PREFIX
    if _PREFIX is not None:
        return _PREFIX

    env = __import__("os").environ.get("OPENFOAM_PREFIX")
    if env:
        root = Path(env).resolve()
        if (root / "etc" / "bashrc").is_file():
            _PREFIX = root
            return _PREFIX

    root = _package_dir()
    installed = root / "prefix"
    bashrc = installed / "etc" / "bashrc"
    if bashrc.is_file():
        _PREFIX = installed
        return _PREFIX

    archive = root / "openfoam-native.tar.gz"
    if not archive.is_file():
        raise FileNotFoundError(
            "Native OpenFOAM install not bundled; use make wheel-dist or cpack-dist"
        )

    installed.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:gz") as tf:
        if hasattr(tarfile, "data_filter"):
            tf.extractall(installed, filter="data")
        else:
            tf.extractall(installed)

    _rewrite_installed_prefix(installed)

    if not bashrc.is_file():
        raise FileNotFoundError(f"Invalid native bundle; missing {bashrc}")

    _PREFIX = installed
    return _PREFIX
