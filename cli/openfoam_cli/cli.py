import os
import sys


def _launcher_path() -> str:
    import openfoam_cli

    return os.path.join(os.path.dirname(openfoam_cli.__file__), "openfoam.sh")


def main() -> None:
    script = _launcher_path()
    if not os.path.isfile(script):
        print(f"Launcher script not found: {script}", file=sys.stderr)
        raise SystemExit(1)
    os.execvp("bash", ["bash", script, *sys.argv[1:]])
