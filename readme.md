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
├── build/              # Compiled OpenFOAM installation
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
| `make wheel-dist` | Native pip wheel + CLI (uses existing `build/`, skips if up to date) |
| `make wheel-install` | wheel-dist + pip install |
| `make cpack-dist` | Native tar.gz + `bin/openfoam` (`build/cpack-dist/`) |
| `make clean` | Remove dist/stage only (keeps `build/` compile tree) |
| `make real-clean` | Remove native `build/` and re-sync submodules |
| `make docker-setup-base` | Pull digest-pinned `phynexis-ubuntu:24.04-{arch}` |
| `make docker-setup-build` | Build `phynexis-build:24.04-{arch}` toolchain image |
| `make docker-build` | Build runtime image `openfoam:24.04-{arch}` |
| `make docker-dist` | Export image + CLI wheel to `build/docker-dist/` |
| `make cli-install` | Install CLI wheel from `build/docker-dist/` |
| `make docker-push` | Push `openfoam` image (set `DOCKER_REGISTRY` in config) |

## Distribution (wheel / cpack / docker)

Three release channels:

| Channel | Make target | Output |
|---------|-------------|--------|
| wheel | `make wheel-dist` | `build/wheel-dist/openfoam-2412-*.whl` (no recompile; tar from `build/`) |
| cpack | `make cpack-dist` | `build/cpack-dist/openfoam-native-*.tar.gz` (install tree + `bin/openfoam`) |
| docker | `make docker-dist` | `build/docker-dist/openfoam-*.tar.gz` + `openfoam-*.whl` (CLI only) |

After `pip install openfoam-*.whl` or extracting cpack, use the `openfoam` command:

```bash
openfoam run ~/my_case/Allrun          # run a case script (native)
openfoam blockMesh -help               # run any OpenFOAM command
eval "$(openfoam env)" && wmake        # link/build extensions against OpenFOAM
openfoam docker pull                   # Docker channel
openfoam docker run ~/my_case/Allrun
```

cpack: extract archive, add `<prefix>/bin` to `PATH`, then run `openfoam`.

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
| Source | `/build/openfoam` | `/build/phynexis-v0` |
| Compile | `/build/openfoam/build` | `/build/phynexis-v0/build` |
| Cache mount | `/cache/openfoam` → `build/` | `/cache/phynexis-v0` → `build/` |
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

After `make install`, either source the environment or use the CLI from the repo:

```bash
source build/etc/bashrc
# or
eval "$(bash cli/openfoam_cli/openfoam.sh env)"
```

### End users (wheel / cpack / docker)

Use `openfoam` instead of manual `source` for running solvers (see Distribution above).
For building projects that link against OpenFOAM, use `openfoam env` once per shell session.

```bash
# Check installation
openfoam blockMesh -help

# Run a tutorial
openfoam run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
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

4. **Clean rebuild**: `make clean` only removes packaging outputs (`wheel-dist`, `docker-dist`, `stage/`, etc.) and keeps the compiled `build/` tree. To wipe the full native build:

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
