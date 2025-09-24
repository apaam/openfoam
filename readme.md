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
openfoam_customized/
├── openfoam_source/     # OpenFOAM source code
├── build/              # Compiled OpenFOAM installation
├── local/              # Local customizations
├── configure.sh        # macOS-specific configuration
├── install.sh          # Cross-platform installation script
├── makefile           # Build system makefile
├── Brewfile           # macOS dependencies
└── readme.md          # This file
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
| `make test` | Run OpenFOAM tests |
| `make clean` | Clean build directory |
| `make realclean` | Remove entire build directory |

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
