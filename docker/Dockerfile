# syntax=docker/dockerfile:1.4
# OpenFOAM runtime image: compile on phynexis-build, distribute on phynexis-ubuntu.

ARG DOCKER_BUILD_IMAGE_NAME=phynexis-build
ARG DOCKER_UBUNTU_IMAGE_NAME=phynexis-ubuntu
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH

FROM ${DOCKER_BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH} AS compile

ARG TARGETARCH
ARG NUM_JOBS=4
ARG OPENFOAM_VERSION=v2412
ARG OPENFOAM_BUILD_MODULES=0
ARG BUILD_STAMP=0

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NUM_JOBS=${NUM_JOBS} \
    OPENFOAM_BUILD_MODULES=${OPENFOAM_BUILD_MODULES}

WORKDIR /build/openfoam
COPY . .

# BUILD_STAMP ensures compile always runs (same as local make); wmake incrementality uses cache mount.
RUN --mount=type=cache,target=/cache/openfoam,id=openfoam-build-${TARGETARCH} \
  echo "build-stamp=${BUILD_STAMP}" \
  && chmod +x docker/bake_openfoam.sh docker/stage_openfoam.sh \
     docker/resolve_runtime_apt.sh scripts/build_openfoam.sh \
  && OPENFOAM_VERSION="${OPENFOAM_VERSION}" NUM_JOBS=${NUM_JOBS} \
     OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES}" \
     ./docker/bake_openfoam.sh

FROM ${DOCKER_UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH} AS fresh

ARG APT_MIRROR=
ARG OPENFOAM_RUNTIME_DEPS_REV=1

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

LABEL org.openfoam.runtime-deps-rev="${OPENFOAM_RUNTIME_DEPS_REV}"

COPY docker/apt_setup.sh /usr/local/bin/apt_setup.sh
COPY docker/openfoam_runtime_install.sh /usr/local/bin/openfoam_runtime_install.sh
COPY --from=compile /build/stage/openfoam.runtime-apt.txt /tmp/openfoam.runtime-apt.txt
RUN chmod +x /usr/local/bin/apt_setup.sh /usr/local/bin/openfoam_runtime_install.sh \
  && APT_MIRROR=${APT_MIRROR} apt_setup.sh \
  && OPENFOAM_RUNTIME_PACKAGES=/tmp/openfoam.runtime-apt.txt openfoam_runtime_install.sh

COPY --from=compile /build/stage/openfoam /opt/openfoam
COPY docker/rewrite_openfoam_paths.sh /usr/local/bin/rewrite_openfoam_paths.sh
RUN chmod +x /usr/local/bin/rewrite_openfoam_paths.sh \
  && rewrite_openfoam_paths.sh /opt/openfoam /build/openfoam/build/openfoam /opt/openfoam \
  && test -f /opt/openfoam/etc/bashrc
