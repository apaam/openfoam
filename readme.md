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
│   ├── openfoam/       # WM_PROJECT_DIR (compile + install tree)
│   ├── stage/          # Packaging staging
│   └── wheel/ ...      # Distribution outputs
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
| `make wheel-dist` | Native pip wheel + CLI (uses existing `build/openfoam/`, skips if up to date) |
| `make wheel-install` | `make wheel` + pip install (local, no dylib bundle) |
| `make cpack-dist` | Native tar.gz + `bin/openfoam` (`build/cpack-dist/`) |
| `make clean` | Remove `build/` (compile cache + packaging) |
| `make real-clean` | `clean` + reset `openfoam-source` + sync-submodule |
| `make docker-setup-base` | Pull digest-pinned `phynexis-ubuntu:24.04-{arch}` |
| `make docker-setup-build` | Build `phynexis-build:24.04-{arch}` toolchain image |
| `make docker-build` | Build runtime image `openfoam:24.04-{arch}` |
| `make docker-dist` | Export image + CLI wheel to `build/docker-dist/` |
| `make cli-install` | Install CLI wheel from `build/docker-dist/` |
| `make docker-push` | Push `openfoam` image (set `DOCKER_REGISTRY` in config) |

## Distribution (wheel / cpack / docker)

Three release channels share the same `openfoam` CLI; Docker adds an `openfoam docker` prefix.

| Channel | Install | Prefix location |
|---------|---------|-----------------|
| local build | `make install` | `build/openfoam/` (CLI: `build/cli/`) |
| wheel | `pip install openfoam-*.whl` | `site-packages/openfoam/prefix/` |
| cpack | `tar xzf ... -C <dir>` | extract root (`<dir>/`) |
| docker | `pip install` CLI + `openfoam docker pull` | `/opt/openfoam` (in container) |

| Make target | Output |
|-------------|--------|
| wheel / wheel-dist | `build/wheel/` or `build/wheel-dist/openfoam-*.whl` |
| cpack / cpack-dist | `build/cpack/` or `build/cpack-dist/openfoam-native-*.tar.gz` |
| docker | `build/docker-dist/openfoam-*.tar.gz` + CLI wheel |

### Shell setup (~/.bashrc)

Load the environment the native OpenFOAM way: `source <prefix>/etc/bashrc`.
Add `openfoam` to PATH only where pip does not (local build / cpack).

```bash
# local build
source /path/to/repo/build/openfoam/etc/bashrc
export PATH="/path/to/repo/build/cli/bin:$PATH"

# cpack
source /path/to/extract/etc/bashrc
export PATH="/path/to/extract/bin:$PATH"

# wheel (prefix path inside site-packages; use openfoam env)
eval "$(openfoam env)"
```

### Install

```bash
# local build
make install

# wheel
pip install build/wheel-dist/openfoam-*.whl

# cpack
tar xzf build/cpack-dist/openfoam-native-*.tar.gz -C ~/opt/openfoam

# docker
pip install build/docker-dist/openfoam-*.whl
openfoam docker pull
```

### Verify (same commands for wheel and cpack)

```bash
openfoam blockMesh -help           # always via openfoam CLI
openfoam docker blockMesh -help    # docker channel
```

After `source .../etc/bashrc`, `blockMesh` is on PATH. Use `openfoam` for run/shell/docker.

### Daily use

```bash
source build/openfoam/etc/bashrc   # or eval "$(openfoam env)" for wheel
openfoam run ~/my_case/Allrun
openfoam shell ~/my_case
wmake                            # after source etc/bashrc
openfoam docker run ~/my_case/Allrun
```

`OPENFOAM_PREFIX` overrides prefix discovery. Local build links CLI to prefix via
`build/cli/.openfoam-prefix`; cpack sets it in `bin/openfoam`; wheel uses `openfoam/prefix/`.

## Docker

Self-contained image stack in this repo:

```
phynexis-ubuntu:24.04-{arch}  →  docker-setup-base
phynexis-build:24.04-{arch}   →  docker-setup-build (compile only)
openfoam:24.04-{arch}         →  docker-build (phynexis-ubuntu + ldd/dpkg runtime deps + /opt/openfoam)
```

Runtime install tree: `/opt/openfoam` (`source /opt/openfoam/etc/bashrc`).

Docker path layout (shared convention with phynexis-v0):

| Role | openfoam | phynexis-v0 |
|------|----------|-------------|
| Repo root | `/build/openfoam` | `/build/phynexis-v0` |
| WM_PROJECT_DIR | `/build/openfoam/build/openfoam` | `/build/phynexis-v0/build/...` |
| wmake objects | `.../build/openfoam/build` | `.../build/.../build` |
| Cache mount | `/cache/openfoam` → `build/openfoam/` | `/cache/phynexis-v0` → `build/` |
| Cache id | `openfoam-build-{arch}` | `phynexis-build-{arch}` |
| Stage | — | `/build/stage/phynexis-v0`, `/build/stage/openfoam` |
| Runtime | `/opt/openfoam` | `/opt/phynexis`, `/opt/openfoam` |

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
source build/openfoam/etc/bashrc
export PATH="build/cli/bin:$PATH"
wmake
```

### End users (wheel / cpack / docker)

Add `source <prefix>/etc/bashrc` to your shell (see Distribution). Use `openfoam` for
run/shell/docker; use `eval "$(openfoam env)"` when the prefix path is not obvious (wheel).

```bash
# Native channels (wheel / cpack)
openfoam blockMesh -help
openfoam run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun

# Docker channel
openfoam docker blockMesh -help
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
