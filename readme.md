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

### Path model

| Variable | Role | Default |
|----------|------|---------|
| `BUILD_ROOT` | Active build tree (compile, pack, `make clean`) | `build` |
| `DOCKER_BUILD_ROOT` | Build tree when `CONTAINER_BUILD=1` (`make docker-shell`) | `docker-build` |
| `OPENFOAM_PREFIX` | Runtime install root (`etc/bashrc`; CLI) | `/opt/openfoam` |

Derived outputs use `$(BUILD_ROOT)/…` (e.g. `openfoam-build`, `dist-native`). Prefer changing the roots; keep derived paths relative to `BUILD_ROOT` so docker-shell remapping stays consistent. `make clean` removes only the current `BUILD_ROOT`.

### Directory Structure

```
openfoam/
├── openfoam-source/      # OpenFOAM source (git submodule)
├── build/                # default BUILD_ROOT (host)
│   ├── bin/              # local CLI (OPENFOAM_CLI_BUILD)
│   ├── share/            # local CLI data + completions
│   ├── openfoam-build/   # WM_PROJECT_DIR (OPENFOAM_BUILD)
│   ├── cli-wheel/        # pip wheel output
│   ├── cli-pack/         # CLI tar.gz
│   ├── openfoam-pack/    # native openfoam tar.gz (dev pack)
│   ├── dist-native/      # host native release bundle
│   ├── dist-docker/      # host docker release bundle
│   ├── stage/            # staging for pack
│   └── docker/           # image build intermediates
├── docker-build/         # DOCKER_BUILD_ROOT (mirrors build/ under docker-shell)
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
| `make openfoam` | Compile OpenFOAM → `$(BUILD_ROOT)/openfoam-build/` |
| `make cli` | Install CLI locally → `$(BUILD_ROOT)/bin/` |
| `make all` | `openfoam` + `cli` + `cli-wheel` |
| `make all-install` | `all` + pip install CLI wheel |
| `make openfoam-pack` | tar.gz from existing build (no bundle) |
| `make dist-native` | Host native release → `$(BUILD_ROOT)/dist-native/` |
| `make cli-wheel` | CLI pip wheel → `$(BUILD_ROOT)/cli-wheel/` |
| `make cli-pack` | CLI tar.gz → `$(BUILD_ROOT)/cli-pack/` |
| `make dist-docker` | Linux host: pack host linux native → `build/dist-docker/` (macOS: use `docker-dist-docker`) |
| `make docker-dist-native` | Container build → `docker-build/dist-native/` |
| `make docker-dist-docker` | Container build + image + CLI → `docker-build/dist-docker/` |
| `make docker-shell` | Interactive build container (`BUILD_ROOT=docker-build`) |
| `make docker-setup-base` | Optional: pull Ubuntu base |
| `make deps` | Install dependencies (macOS only) |
| `make clean` | Remove current `$(BUILD_ROOT)/` |
| `make clean-all` | Remove host and docker-shell trees (`HOST_BUILD_ROOT` + `DOCKER_BUILD_ROOT`) |
| `make real-clean` | `clean` + reset `openfoam-source` |

## Distribution

Release bundles: `dist-native` (per-host native tar + CLI), `dist-docker` (Linux Docker image + CLI; no macOS image). Intermediate packs: `openfoam-pack`, `cli-pack`, `cli-wheel`.

### CLI reference

Top-level: `openfoam help`, `openfoam docker help`.

| Command | Purpose |
|---------|---------|
| `prefix` | Print install root (`OPENFOAM_PREFIX` or default `/opt/openfoam`) |
| `completion bash\|zsh` | Tab completion |
| `run [-np N] <cmd> [args]` | Run a command in the current directory |
| `shell [dir]` | Interactive shell with OpenFOAM environment |
| `docker pull` | Pull runtime image |
| `docker install-image [tar]` | Load offline image (`make dist-docker`); pass path when CLI is pip-installed |
| `docker uninstall-image` | Remove runtime image |
| `docker run …` / `docker shell …` | Same commands inside container (`/root/.bashrc`) |

| Channel | Install openfoam | Install CLI |
|---------|------------------|-------------|
| local dev | `make all` | `$(BUILD_ROOT)/bin/openfoam` or `make all-install` |
| macOS / Linux native | `tar xzf openfoam-native-*.tar.gz -C <prefix>` (`make dist-native`) | `pip install openfoam_cli-*.whl` or `tar xzf openfoam-cli-*.tar.gz` |
| Docker (Linux image only) | `openfoam docker install-image` (`make dist-docker` on Linux / CI; `make docker-dist-docker` on macOS) | host `pip install openfoam_cli-*.whl` |

| Make target | Output |
|-------------|--------|
| `dist-native` | `build/dist-native/` — host `openfoam-native-*.tar.gz`, CLI wheel/pack |
| `dist-docker` | `build/dist-docker/` — Linux host image + CLI |
| `docker-dist-native` | `docker-build/dist-native/` — container linux native |
| `docker-dist-docker` | `docker-build/dist-docker/` — container image + CLI |
| `cli-wheel` | `build/cli-wheel/openfoam_cli-*.whl` |

### Shell setup

Load OpenFOAM the native way: `source <prefix>/etc/bashrc`.

```bash
# local dev (BUILD_ROOT=build)
source build/openfoam-build/etc/bashrc
export PATH="build/bin:$PATH"

# native release (dist-native)
mkdir -p ~/opt/openfoam && tar xzf build/dist-native/openfoam-native-*.tar.gz -C ~/opt/openfoam
source ~/opt/openfoam/etc/bashrc
export OPENFOAM_PREFIX=~/opt/openfoam
pip install build/dist-native/openfoam_cli-*.whl
# or: tar xzf build/dist-native/openfoam-cli-*.tar.gz -C ~/opt/cli && export PATH=~/opt/cli/bin:$PATH

# docker (pip-installed CLI does not auto-find repo dist-docker/)
pip install build/dist-docker/openfoam_cli-*.whl
openfoam docker install-image build/dist-docker/openfoam-docker-2412-linux-amd64.tar.gz
# Apple Silicon Docker: openfoam-docker-*-linux-arm64.tar.gz
# or: OPENFOAM_PACK=/path/to/openfoam-docker-2412-linux-amd64.tar.gz openfoam docker install-image
```

### Verify

```bash
eval "$(openfoam prefix)"
source "$OPENFOAM_PREFIX/etc/bashrc"
# or: source "$(openfoam prefix --path)/etc/bashrc"
blockMesh -help
(cd "$FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily" && openfoam run ./Allrun)
(cd "$FOAM_TUTORIALS/incompressible/simpleFoam/pitzDaily" && openfoam docker run ./Allrun)
# openfoam run -np 4 icoFoam -parallel
```

## Docker

Docker (Linux image only; Docker Desktop on macOS/Windows still runs Linux containers). macOS users who want a native install use `make dist-native`; there is no macOS Docker image.

`dist-docker` (Linux host) packs `build/dist-native/openfoam-native-*-linux-*.tar.gz` into a runtime image under `build/dist-docker/`. On macOS use `docker-dist-docker` (compiles in container → `docker-build/`). Release builds **amd64** and **arm64** images from matching Linux artifacts. `docker-*` targets must run on the host (not inside `docker-shell`).

```
phynexis-build:24.04-{arch}   →  docker-setup-build / docker-shell
phynexis-ubuntu:24.04-{arch}  →  docker-setup-base
openfoam-native-*-linux-*.tar.gz  →  dist-docker / docker-dist-docker
openfoam:24.04-{arch}          →  runtime image
build/dist-docker/             →  host release (make dist-docker)
docker-build/dist-docker/      →  container release (make docker-dist-docker)
```

```bash
# Linux host
make dist-native
make dist-docker
make docker-push

# macOS / isolated Linux build on any host
make docker-dist-docker
```

Path variables: `BUILD_ROOT` / `DOCKER_BUILD_ROOT` / derived paths in `docs/make-config-default.mk`; override in `make-config-user.mk`. Runtime install: `OPENFOAM_PREFIX`.

## Usage

### Development

After `make all`:

```bash
source build/openfoam-build/etc/bashrc
export PATH="build/bin:$PATH"
wmake
```

Inside `make docker-shell`, the same commands use `docker-build/` instead of `build/`.

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
2. **Permission errors**: Check write permissions on `$(BUILD_ROOT)/` (`build/` or `docker-build/`)
3. **Memory issues**: `make -j2 openfoam`
4. **Clean rebuild**: `make real-clean && make all` (only current `BUILD_ROOT`; use `make clean-all` to wipe both `build/` and `docker-build/`)

## License

This build system is provided under the same license as OpenFOAM.

## Links

- [OpenFOAM Official Website](http://www.openfoam.com/)
- [OpenFOAM Documentation](http://www.openfoam.com/documentation)
- [OpenFOAM Source Code](https://develop.openfoam.com/Development/openfoam/)
