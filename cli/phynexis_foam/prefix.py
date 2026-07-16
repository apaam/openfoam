"""Resolve native OpenFOAM install prefix."""

from __future__ import annotations

import os
import shlex
import sys
from pathlib import Path
from typing import Optional

_PREFIX: Optional[Path] = None
_REWRITE_MARKER = ".prefix-rewritten"
DEFAULT_OPENFOAM_PREFIX = "/opt/openfoam"


def _package_dir() -> Path:
    return Path(__file__).resolve().parent


def _has_bashrc(root: Path) -> bool:
    product = root / "etc" / "bashrc"
    upstream = root / "openfoam" / "etc" / "bashrc"
    if product.is_file() and upstream.is_file():
        return True
    if product.is_file() and not (root / "openfoam").is_dir():
        return True
    return False


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

                of_tree = installed / "openfoam"
                target = of_tree if (of_tree / "etc" / "bashrc").is_file() else installed
                subprocess.run(
                    ["bash", str(script), str(target), old_prefix, new_prefix],
                    check=True,
                )
    rewritten.write_text(str(installed.resolve()), encoding="utf-8")


def _local_build_prefix() -> Optional[Path]:
    pkg_dir = _package_dir()
    if not str(pkg_dir).endswith("/share/phynexis-foam/cli"):
        return None
    cli_root = pkg_dir.parent.parent.parent.resolve()
    if (cli_root / "etc" / "bashrc").is_file():
        return cli_root
    return None


def runtime_prefix() -> Path:
    """User-facing install root; does not require etc/bashrc."""
    env = os.environ.get("OPENFOAM_PREFIX")
    if env:
        return Path(env).expanduser().resolve()

    local = _local_build_prefix()
    if local is not None:
        return local

    return Path(DEFAULT_OPENFOAM_PREFIX)


def native_prefix() -> Path:
    """Installed prefix with etc/bashrc (OPENFOAM_PREFIX or local build)."""
    global _PREFIX
    if _PREFIX is not None:
        return _PREFIX

    root = runtime_prefix()
    if not _has_bashrc(root):
        raise FileNotFoundError(
            f"OpenFOAM install not found at {root}; "
            f"extract phynexis-foam tar or set OPENFOAM_PREFIX"
        )

    _rewrite_installed_prefix(root)
    _PREFIX = root
    return _PREFIX


def format_prefix_output(path: Path, *, bare: bool = False) -> str:
    text = str(path)
    if bare:
        return text
    return f"OPENFOAM_PREFIX={shlex.quote(text)}"


def main() -> None:
    args = sys.argv[1:]
    bare = "--path" in args or "-p" in args
    if "--runtime" in args:
        path = runtime_prefix()
    else:
        path = native_prefix()
    print(format_prefix_output(path, bare=bare))


if __name__ == "__main__":
    main()
