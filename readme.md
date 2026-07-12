# OpenFOAM Customized Build System

This repository contains a customized build system for OpenFOAM, designed to simplify the compilation and installation process across different platforms, with special optimizations for macOS.

## Features

- **Version via config**: Set `OPENFOAM_VERSION` in `make-config-user.mk`
- **Cross-platform compatibility**: macOS and Linux support
- **Automated dependency management**: Uses Homebrew on macOS for dependency resolution
- **Parallel compilation**: Configurable parallel build jobs
- **Clean build system**: Easy cleanup and rebuild options

## Quick Start

### Prerequisites

#### macOS (Recommended)
The build system automatically handles dependencies using Homebrew:

```bash
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

```bash
make all
```

Set `OPENFOAM_VERSION` in `make-config-user.mk` and checkout the matching tag in `openfoam-source` before building.

```bash
make -j8 openfoam
```

## Build System Overview

### Directory Structure

```
openfoam/
├── openfoam-source/      # OpenFOAM source (git submodule)
├── build/
│   ├── openfoam-build/   # WM_PROJECT_DIR (native; OPENFOAM_BUILD)
│   ├── cli/              # local CLI (OPENFOAM_CLI_BUILD)
│   ├── cli-wheel/        # pip wheel output
│   ├── cli-pack/         # CLI tar.gz
│   ├── openfoam-pack/    # native openfoam tar.gz (dev pack)
│   ├── openfoam-dist/    # native release bundle
│   ├── docker-build/     # WM_PROJECT_DIR (docker; DOCKER_OPENFOAM_BUILD)
│   ├── stage/            # staging for pack / docker image
│   ├── docker/           # docker image tar (intermediate)
│   └── docker-dist/      # docker release bundle
├── cli/                  # openfoam CLI sources
├── docker/               # Docker image build scripts
├── scripts/              # Build and packaging scripts
├── configure.sh          # macOS-specific configuration
├── install.sh            # Cross-platform installation script
├── makefile              # Build system makefile
└── readme.md
```

### Available Make Targets

| Target | Description |
|--------|-------------|
| `make help` | List main targets (default) |
| `make openfoam` | Compile OpenFOAM locally → `build/openfoam-build/` |
| `make cli` | Install CLI locally → `build/cli/` |
| `make all` | `openfoam` + `cli` + `cli-wheel` |
| `make install` | pip install CLI wheel |
| `make openfoam-pack` | tar.gz from existing build (no bundle) |
| `make openfoam-dist` | Release bundle → `build/openfoam-dist/` |
| `make cli-wheel` | CLI pip wheel → `build/cli-wheel/` |
| `make cli-pack` | CLI tar.gz → `build/cli-pack/` |
| `make docker-build` | Docker compile + runtime image |
| `make docker-dist` | Release bundle → `build/docker-dist/` |
| `make deps` | Install dependencies (macOS only) |
| `make clean` | Remove `build/` |
| `make real-clean` | `clean` + reset `openfoam-source` |

## Distribution

Release bundles (`openfoam-dist`, `docker-dist`) ship OpenFOAM (native tar or image tar), CLI (`openfoam-cli-*.tar.gz` and `openfoam-*.whl`). Intermediate packs: `openfoam-pack`, `cli-pack`, `cli-wheel`.

### CLI reference

Top-level: `openfoam help`, `openfoam docker help`.

| Command | Purpose |
|---------|---------|
| `prefix` | Print install root (`OPENFOAM_PREFIX` or default `/opt/openfoam`) |
| `completion bash\|zsh` | Tab completion |
| `run <script> [args]` | Run Allrun or another script in its directory |
| `shell [dir]` | Interactive shell with OpenFOAM environment |
| `docker pull` | Pull runtime image |
| `docker install-image [tar]` | Load offline image (`make docker-dist`); pass path when CLI is pip-installed |
| `docker uninstall-image` | Remove runtime image |
| `docker run …` / `docker shell …` | Run scripts or shell inside container |

| Channel | Install openfoam | Install CLI |
|---------|------------------|-------------|
| local dev | `make all` | `build/cli/bin/openfoam` or `make install` |
| native release | `tar xzf openfoam-native-*.tar.gz -C <prefix>` | `pip install openfoam-*.whl` or `tar xzf openfoam-cli-*.tar.gz -C <prefix>` |
| docker | `openfoam docker install-image` | host `pip install openfoam-*.whl` |

| Make target | Output |
|-------------|--------|
| `openfoam-dist` | `build/openfoam-dist/` — `openfoam-native-*.tar.gz`, `openfoam-cli-*.tar.gz`, `openfoam-*.whl` |
| `cli-wheel` | `build/cli-wheel/openfoam-*.whl` |
| `docker-dist` | `build/docker-dist/` — `openfoam-docker-*.tar.gz`, `openfoam-cli-*.tar.gz`, `openfoam-*.whl` |

### Shell setup

Load OpenFOAM the native way: `source <prefix>/etc/bashrc`.

```bash
# local dev
source build/openfoam-build/etc/bashrc
export PATH="build/cli/bin:$PATH"

# native release (openfoam-dist)
mkdir -p ~/opt/openfoam && tar xzf build/openfoam-dist/openfoam-native-*.tar.gz -C ~/opt/openfoam
source ~/opt/openfoam/etc/bashrc
export OPENFOAM_PREFIX=~/opt/openfoam
pip install build/openfoam-dist/openfoam-*.whl
# or: tar xzf build/openfoam-dist/openfoam-cli-*.tar.gz -C ~/opt/cli && export PATH=~/opt/cli/bin:$PATH

# docker (pip-installed CLI does not auto-find repo build/docker-dist/)
pip install build/docker-dist/openfoam-*.whl
openfoam docker install-image build/docker-dist/openfoam-docker-2412-linux-amd64.tar.gz
# or: OPENFOAM_PACK=/path/to/openfoam-docker-2412-linux-amd64.tar.gz openfoam docker install-image
```

### Verify

```bash
eval "$(openfoam prefix)"
source "$OPENFOAM_PREFIX/etc/bashrc"
# or: source "$(openfoam prefix --path)/etc/bashrc"
blockMesh -help
openfoam run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
openfoam docker run $FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily/Allrun
```

## Docker

```
phynexis-ubuntu:24.04-{arch}  →  docker-setup-base
phynexis-build:24.04-{arch}   →  docker-setup-build
build/docker-build/            →  docker-build (DOCKER_OPENFOAM_BUILD)
openfoam:24.04-{arch}          →  runtime image
build/docker-dist/             →  release bundle (image + cli-pack + wheel)
```

```bash
make docker-build
make docker-dist
make docker-push
```

Use `FORCE=1 make docker-build` to rebuild the toolchain image when needed.

Path variables: `docs/make-config-default.mk`, override in `make-config-user.mk`.

## Usage

### Development

After `make all`:

```bash
source build/openfoam-build/etc/bashrc
export PATH="build/cli/bin:$PATH"
wmake
```

### End users

Set `OPENFOAM_PREFIX` to your install root (default `/opt/openfoam`). Use a case-sensitive volume on macOS when extracting native tarballs.

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

1. **Build fails on macOS**: `make deps`
2. **Permission errors**: Check write permissions on `build/`
3. **Memory issues**: `make -j2 openfoam`
4. **Clean rebuild**: `make real-clean && make all`

## License

This build system is provided under the same license as OpenFOAM.

## Links

- [OpenFOAM Official Website](http://www.openfoam.com/)
- [OpenFOAM Documentation](http://www.openfoam.com/documentation)
- [OpenFOAM Source Code](https://develop.openfoam.com/Development/openfoam/)
