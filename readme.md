# OpenFOAM Customized Build System

This repository contains a customized build system for OpenFOAM, designed to simplify the compilation and installation process across different platforms, with special optimizations for macOS.

## Features

- **Multi-version support**: Build OpenFOAM v2112 or v2412
- **Cross-platform compatibility**: macOS and Linux support
- **Automated dependency management**: Uses Homebrew on macOS for dependency resolution
- **Parallel compilation**: Configurable parallel build jobs
- **Clean build system**: Easy cleanup and rebuild options

## Quick Start

### Prerequisites

#### macOS (Recommended)
The build system automatically handles dependencies using Homebrew:

```bash
# Install dependencies automatically
make deps
```

#### Linux (Ubuntu/Debian)
Install required packages manually:

```bash
sudo apt-get update
sudo apt-get install build-essential cmake
sudo apt-get install libopenmpi-dev openmpi-bin zlib1g-dev libboost-system-dev libboost-thread-dev 
sudo apt-get install rsync flex bison gnuplot libreadline-dev libncurses-dev libxt-dev 
```

### Installation

#### Default Installation (v2412)
```bash
make
```

#### Specific Version Installation
```bash
# Install OpenFOAM v2112
make v2112

# Install OpenFOAM v2412
make v2412
```

#### Custom Parallel Jobs
```bash
# Use 8 parallel jobs
make -j8

# Or set environment variable
NUM_JOBS=8 make
```

## Build System Overview

### Directory Structure
```
openfoam/
├── openfoam-source/    # OpenFOAM source (git submodule)
├── build/              # Local build workspace
│   ├── host-build/     # WM_PROJECT_DIR (native compile; OPENFOAM_BUILD)
│   ├── docker-build/   # WM_PROJECT_DIR (Docker/Linux compile; DOCKER_OPENFOAM_BUILD)
│   ├── stage/          # host-build + docker-build staging
│   └── docker/         # Docker image tar + CLI wheel
│   └── docker-dist/    # Docker release bundle
├── cli/                # openfoam CLI (wheel / cpack / docker)
├── docker/             # Docker image build scripts
├── local/              # Local customizations
├── scripts/            # Build and packaging scripts
├── configure.sh        # macOS-specific configuration
├── install.sh          # Cross-platform installation script
├── makefile            # Build system makefile
├── Brewfile            # macOS dependencies
└── readme.md           # This file
```

### Key Components

- **`makefile`**: Main build system with targets for different OpenFOAM versions
- **`install.sh`**: Cross-platform installation script that handles both macOS and Linux
- **`configure.sh`**: macOS-specific configuration for Homebrew dependencies
- **`Brewfile`**: Defines all required dependencies for macOS

### Available Make Targets

| Target | Description |
|--------|-------------|
| `make help` | List main targets |
| `make` | Build default version (v2412) |
| `make v2112` | Build OpenFOAM v2112 |
| `make v2412` | Build OpenFOAM v2412 |
| `make deps` | Install dependencies (macOS only) |
| `make wheel-dist` | Native pip wheel + CLI (uses existing `OPENFOAM_BUILD`, skips if up to date) |
| `make wheel-install` | `make wheel` + pip install (local, no dylib bundle) |
| `make cpack-dist` | Native tar.gz + `bin/openfoam` (`build/cpack-dist/`) |
| `make clean` | Remove `build/` (compile cache + packaging) |
| `make real-clean` | `clean` + reset `openfoam-source` + sync-submodule |
| `make docker-setup-base` | Pull digest-pinned `phynexis-ubuntu:24.04-{arch}` |
| `make docker-setup-build` | Build `phynexis-build:24.04-{arch}` toolchain image |
| `make docker-build` | `docker run` compile → `DOCKER_OPENFOAM_BUILD/`, then runtime image |
| `make docker-dist` | Package `build/docker/` → `build/docker-dist/` |
| `make cli-install` | Install CLI wheel from `build/docker-dist/` or `build/docker/` |
| `make docker-push` | Push `openfoam` image (set `DOCKER_REGISTRY` in config) |

## Distribution (wheel / cpack / docker)

Three release channels share the same `openfoam` CLI; Docker adds an `openfoam docker` prefix.

### CLI reference

Top-level: `openfoam help`, `openfoam docker help`, `openfoam dev help`.

| Command | Purpose |
|---------|---------|
| `prefix` | Print install root (`OPENFOAM_PREFIX` or default `/opt/openfoam`) |
| `dev install` | Extract full OpenFOAM tree into `OPENFOAM_PREFIX` (wheel channel) |
| `dev clean` | Remove entire `OPENFOAM_PREFIX` |
| `completion bash\|zsh` | Print tab-completion script (pip install registers it automatically) |
| `run <script> [args]` | Run Allrun or another script in its directory |
| `shell [dir]` | Interactive shell with OpenFOAM environment |
| `docker pull` | Pull runtime image |
| `docker install-image [tar]` | Load offline image (`make docker-dist`) |
| `docker uninstall-image` | Remove runtime image |
| `docker run …` / `docker shell …` | Run scripts or shell inside container |

Environment: `OPENFOAM_PREFIX` (your install root, set in shell), `OPENFOAM_IMAGE`, `OPENFOAM_PACK`.

| Channel | Install | Prefix location |
|---------|---------|-----------------|
| local build | `make install` | `OPENFOAM_BUILD` (default `build/host-build/`; CLI: `build/cli/`) |
| wheel | `pip install` + `openfoam dev install` | `OPENFOAM_PREFIX` (default `/opt/openfoam`) |
| cpack | `tar xzf ... -C <dir>` | extract root (`<dir>/`) |
| docker | `pip install` CLI + `openfoam docker pull` | `/opt/openfoam` (in container) |

| Make target | Output |
|-------------|--------|
| wheel / wheel-dist | `build/wheel/` or `build/wheel-dist/openfoam-*.whl` |
| cpack / cpack-dist | `build/cpack/` or `build/cpack-dist/openfoam-native-*.tar.gz` |
| docker-build / docker-dist | `DOCKER_OPENFOAM_BUILD` + `build/docker/` or `build/docker-dist/` |

### Shell setup (~/.bashrc)

Load the environment the native OpenFOAM way: `source <prefix>/etc/bashrc`.
Add `openfoam` to PATH only where pip does not (local build / cpack).

```bash
# cpack
source /path/to/extract/etc/bashrc
export PATH="/path/to/extract/bin:$PATH"
fpath=(/path/to/extract/share/zsh/site-functions $fpath)

# local build
source /path/to/repo/build/host-build/etc/bashrc
export PATH="/path/to/repo/build/cli/bin:$PATH"
fpath=(/path/to/repo/build/cli/share/zsh/site-functions $fpath)

# wheel (CLI only from pip; prefix via dev install — same layout as cpack)
pip install build/wheel-dist/openfoam-*.whl
openfoam dev install
source "$(openfoam prefix)/etc/bashrc"
# pip install also registers zsh/bash tab completion automatically
# (requires compinit in zsh, bash-completion in bash)
```

### Install

```bash
# local build
make install

# wheel
pip install build/wheel-dist/openfoam-*.whl
openfoam dev install

# cpack
tar xzf build/cpack-dist/openfoam-native-*.tar.gz -C ~/opt/openfoam

# docker
pip install build/docker-dist/openfoam-*.whl
openfoam docker pull
```

### Verify (same commands for wheel and cpack)

```bash
source "$(openfoam prefix)/etc/bashrc"
blockMesh -help
openfoam run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
openfoam docker run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
```

After `source .../etc/bashrc`, OpenFOAM apps are on PATH. Use `openfoam` for install/run/shell/docker.

### Daily use

```bash
source build/host-build/etc/bashrc   # OPENFOAM_BUILD; or wheel/cpack prefix
openfoam run ~/my_case/Allrun
openfoam shell ~/my_case
wmake                            # after source etc/bashrc
openfoam docker run ~/my_case/Allrun
```

`OPENFOAM_PREFIX` is the install root for wheel and cpack. Local build links CLI to prefix via
`build/cli/.openfoam-prefix`; cpack sets it in `bin/openfoam`.

Wheel pip package is CLI only; `openfoam dev install` extracts the full prefix tree to
`OPENFOAM_PREFIX` (same layout as cpack). Use a case-sensitive volume on macOS.

```bash
pip install build/wheel/openfoam-*.whl

export OPENFOAM_PREFIX=/Volumes/OpenFOAM/opt/openfoam   # optional; default /opt/openfoam
openfoam dev install
source "${OPENFOAM_PREFIX}/etc/bashrc"
wmake
openfoam dev clean   # remove entire OPENFOAM_PREFIX
```

Default `OPENFOAM_PREFIX` is `/opt/openfoam` when unset.

## Docker

Self-contained image stack in this repo:

```
phynexis-ubuntu:24.04-{arch}  →  docker-setup-base
phynexis-build:24.04-{arch}   →  docker-setup-build (toolchain)
build/host-build/             →  make install (OPENFOAM_BUILD)
build/docker-build/           →  docker run + build_openfoam.sh (DOCKER_OPENFOAM_BUILD)
build/stage/docker-build/     →  staged install tree for runtime image
openfoam:24.04-{arch}         →  docker build fresh stage → /opt/openfoam
build/docker/                 →  image tar.gz + cli wheel
build/docker-dist/            →  docker-dist release bundle
```

Compile uses the **same** `scripts/build_openfoam.sh` as `make install`, with the repo bind-mounted into the container. Incremental builds persist under `DOCKER_OPENFOAM_BUILD` on the host.

Path variables (`docs/make-config-default.mk`):

| Variable | Default | Role |
|----------|---------|------|
| `OPENFOAM_BUILD` | `build/host-build` | Native WM_PROJECT_DIR |
| `OPENFOAM_STAGE` | `build/stage/host-build` | Native wheel/cpack stage |
| `DOCKER_OPENFOAM_BUILD` | `build/docker-build` | Docker WM_PROJECT_DIR |
| `DOCKER_OPENFOAM_STAGE` | `build/stage/docker-build` | Docker runtime image stage |

| Role | Path |
|------|------|
| Repo root (in container) | `/build/openfoam` |
| WM_PROJECT_DIR (docker) | `DOCKER_OPENFOAM_BUILD` |
| WM_PROJECT_DIR (native) | `OPENFOAM_BUILD` |
| Runtime (in image) | `/opt/openfoam` |

```bash
make docker-build
make docker-dist
make docker-push
```

`docker-setup-build` is skipped when `phynexis-build:24.04-{arch}` already exists;
use `FORCE=1 make docker-build` to rebuild the toolchain image.

Build parallelism and arch: edit `make-config-user.mk` (`BUILD_JOBS`, `DOCKER_JOBS`,
`DOCKER_ARCH`). Defaults are in `docs/make-config-default.mk`.

## Usage

### Development (from source tree)

After `make install`:

```bash
source build/host-build/etc/bashrc
export PATH="build/cli/bin:$PATH"
wmake
```

### End users (wheel / cpack / docker)

Add `source <prefix>/etc/bashrc` to your shell (see Distribution). Set `OPENFOAM_PREFIX`
to your install root; use `openfoam dev install` to populate it from the wheel.

```bash
# Native channels (wheel / cpack)
source "$(openfoam prefix)/etc/bashrc"
blockMesh -help
openfoam run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun

# Docker channel
openfoam docker run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
```

## Dependencies

### macOS (via Homebrew)
- bash, open-mpi, libomp
- adios2, boost, cmake, fftw
- kahip, metis, cgal, scotch
- flex

### Linux
- build-essential, cmake
- openmpi, boost libraries
- zlib, flex, bison, gnuplot
- readline, ncurses, xt development libraries

## Troubleshooting

### Common Issues

1. **Build fails on macOS**: Ensure all Homebrew dependencies are installed
   ```bash
   make deps
   ```

2. **Permission errors**: Make sure you have write permissions to the build directory

3. **Memory issues**: Reduce parallel jobs if you encounter out-of-memory errors
   ```bash
   make -j2  # Use only 2 parallel jobs
   ```

4. **Clean rebuild**: `make clean` removes the entire `build/` workspace (compile cache and packaging). To also reset the `openfoam-source` submodule:

   ```bash
   make real-clean
   make
   ```

## License

This build system is provided under the same license as OpenFOAM. OpenFOAM is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

## Links

- [OpenFOAM Official Website](http://www.openfoam.com/)
- [OpenFOAM Documentation](http://www.openfoam.com/documentation)
- [OpenFOAM Source Code](https://develop.openfoam.com/Development/openfoam/) 
