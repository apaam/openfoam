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
├── docker/             # Docker image (openfoam:24.04-{arch})
├── local/              # Local customizations
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
| `make` | Build default version (v2412) |
| `make v2112` | Build OpenFOAM v2112 |
| `make v2412` | Build OpenFOAM v2412 |
| `make deps` | Install dependencies (macOS only) |
| `make clean` | Remove `build/docker-dist` exports |
| `make real-clean` | Remove native `build/` and re-sync submodules |
| `make docker-setup-base` | Pull digest-pinned `phynexis-ubuntu:24.04-{arch}` |
| `make docker-setup-build` | Build `phynexis-build:24.04-{arch}` toolchain image |
| `make docker-build` | Build runtime image `openfoam:24.04-{arch}` |
| `make docker-dist` | Save `openfoam` image as `build/docker-dist/*.tar.gz` |
| `make docker-push` | Push `openfoam` image (set `DOCKER_REGISTRY` in config) |

## Docker

Self-contained image stack in this repo:

```
phynexis-ubuntu:24.04-{arch}  →  docker-setup-base
phynexis-build:24.04-{arch}   →  docker-setup-build
openfoam:24.04-{arch}         →  docker-build
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

Build parallelism and arch: edit `make-config-user.mk` (`BUILD_JOBS`, `DOCKER_JOBS`,
`DOCKER_ARCH`). Defaults are in `docs/make-config-default.mk`.

## Usage

After successful installation, source the OpenFOAM environment:

```bash
# For bash
source build/etc/bashrc

# For csh/tcsh
source build/etc/cshrc
```

Then you can use OpenFOAM tools:

```bash
# Check installation
foamSystemCheck

# Run a tutorial
cd $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily
./Allrun
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

4. **Clean rebuild**: If you encounter build issues, try a clean rebuild
   ```bash
   make clean
   make
   ```

## License

This build system is provided under the same license as OpenFOAM. OpenFOAM is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

## Links

- [OpenFOAM Official Website](http://www.openfoam.com/)
- [OpenFOAM Documentation](http://www.openfoam.com/documentation)
- [OpenFOAM Source Code](https://develop.openfoam.com/Development/openfoam/) 
