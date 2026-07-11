"""Resolve native OpenFOAM install prefix (wheel layout)."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from typing import Optional

_PREFIX: Optional[Path] = None
_REWRITE_MARKER = ".prefix-rewritten"


def _package_dir() -> Path:
    return Path(__file__).resolve().parent


def _native_install_dir() -> Path:
    return _package_dir() / "prefix"


def _legacy_xdg_roots() -> list[Path]:
    import openfoam

    version = openfoam.__version__
    roots: list[Path] = [Path.home() / ".local" / "share" / "openfoam" / version]
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        roots.append(Path(xdg) / "openfoam" / version)
    return roots


def _cleanup_legacy_xdg() -> None:
    for root in _legacy_xdg_roots():
        prefix = root / "prefix"
        if prefix.is_dir():
            shutil.rmtree(prefix)
        if root.is_dir() and not any(root.iterdir()):
            root.rmdir()
        parent = root.parent
        if parent.is_dir() and parent.name == "openfoam" and not any(parent.iterdir()):
            parent.rmdir()


def _rewrite_installed_prefix(installed: Path) -> None:
    marker = installed / ".pack-source-prefix"
    rewritten = installed / _REWRITE_MARKER
    if rewritten.is_file():
        return
    if marker.is_file():
        old_prefix = marker.read_text(encoding="utf-8").strip()
        new_prefix = str(installed.resolve())
        if old_prefix and old_prefix != new_prefix:
            script = _package_dir() / "rewrite_openfoam_paths.sh"
            if script.is_file():
                import subprocess

                subprocess.run(
                    ["bash", str(script), str(installed), old_prefix, new_prefix],
                    check=True,
                )
    rewritten.write_text(str(installed.resolve()), encoding="utf-8")


def native_prefix() -> Path:
    global _PREFIX
    if _PREFIX is not None:
        return _PREFIX

    env = os.environ.get("OPENFOAM_PREFIX")
    if env:
        root = Path(env).resolve()
        if (root / "etc" / "bashrc").is_file():
            _PREFIX = root
            return _PREFIX

    _cleanup_legacy_xdg()

    installed = _native_install_dir()
    bashrc = installed / "etc" / "bashrc"
    if not bashrc.is_file():
        raise FileNotFoundError(
            "Native OpenFOAM install not bundled; use make wheel-dist or cpack-dist"
        )

    _rewrite_installed_prefix(installed)
    _PREFIX = installed
    return _PREFIX


def main() -> None:
    print(native_prefix())


if __name__ == "__main__":
    main()
