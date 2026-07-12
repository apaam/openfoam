"""Resolve native OpenFOAM install prefix."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

_PREFIX: Optional[Path] = None
_REWRITE_MARKER = ".prefix-rewritten"
DEFAULT_OPENFOAM_PREFIX = "/opt/openfoam"


def _package_dir() -> Path:
    return Path(__file__).resolve().parent


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


def _local_build_prefix() -> Optional[Path]:
    pkg_dir = _package_dir()
    if not str(pkg_dir).endswith("/share/openfoam/cli"):
        return None
    cli_root = pkg_dir.parent.parent.parent.resolve()
    marker = cli_root / ".openfoam-prefix"
    if marker.is_file():
        return Path(marker.read_text(encoding="utf-8").strip()).resolve()
    bashrc = cli_root / "etc" / "bashrc"
    if bashrc.is_file():
        return cli_root
    return None


def runtime_prefix() -> Path:
    """User-facing install root; does not require etc/bashrc."""
    local = _local_build_prefix()
    if local is not None:
        return local

    env = os.environ.get("OPENFOAM_PREFIX")
    if env:
        return Path(env).expanduser().resolve()

    return Path(DEFAULT_OPENFOAM_PREFIX)


def native_prefix() -> Path:
    """Installed prefix with etc/bashrc (OPENFOAM_PREFIX or local build)."""
    global _PREFIX
    if _PREFIX is not None:
        return _PREFIX

    root = runtime_prefix()
    if not (root / "etc" / "bashrc").is_file():
        raise FileNotFoundError(
            f"OpenFOAM install not found at {root}; run: openfoam dev install"
        )

    _rewrite_installed_prefix(root)
    _PREFIX = root
    return _PREFIX


def main() -> None:
    if "--runtime" in sys.argv[1:]:
        print(runtime_prefix())
    else:
        print(native_prefix())


if __name__ == "__main__":
    main()
