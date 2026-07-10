#!/usr/bin/env bash
set -euo pipefail

apt-get install -y --no-install-recommends \
  build-essential \
  rsync \
  git \
  cmake \
  ninja-build \
  patchelf \
  gfortran \
  lld \
  openmpi-bin \
  libopenmpi-dev \
  libboost-all-dev \
  libomp-dev \
  libgmp-dev \
  automake \
  autoconf \
  autoconf-archive \
  libtool \
  texinfo \
  flex \
  libfl-dev \
  bison \
  zlib1g-dev \
  libreadline-dev \
  libncurses-dev \
  libxt-dev \
  python3 \
  python3-pip \
  python3-venv \
  ca-certificates

python3 -m pip install --break-system-packages setuptools wheel mpi4py

rm -rf /var/lib/apt/lists/*
