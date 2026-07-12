# syntax=docker/dockerfile:1.4
# OpenFOAM runtime image: stage tree via --build-context of-stage=$(DOCKER_OPENFOAM_STAGE).

ARG DOCKER_UBUNTU_IMAGE_NAME=phynexis-ubuntu
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH
ARG DOCKER_OPENFOAM_BUILD=build/docker-build

FROM ${DOCKER_UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH} AS fresh

ARG APT_MIRROR=
ARG OPENFOAM_RUNTIME_DEPS_REV=1
ARG DOCKER_OPENFOAM_BUILD=build/docker-build

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

LABEL org.openfoam.runtime-deps-rev="${OPENFOAM_RUNTIME_DEPS_REV}"

COPY docker/apt_setup.sh /usr/local/bin/apt_setup.sh
COPY docker/openfoam_runtime_install.sh /usr/local/bin/openfoam_runtime_install.sh
COPY --from=of-stage runtime-apt.txt /tmp/openfoam.runtime-apt.txt
RUN chmod +x /usr/local/bin/apt_setup.sh /usr/local/bin/openfoam_runtime_install.sh \
  && APT_MIRROR=${APT_MIRROR} apt_setup.sh \
  && OPENFOAM_RUNTIME_PACKAGES=/tmp/openfoam.runtime-apt.txt openfoam_runtime_install.sh

COPY --from=of-stage / /opt/openfoam/
COPY docker/rewrite_openfoam_paths.sh /usr/local/bin/rewrite_openfoam_paths.sh
RUN chmod +x /usr/local/bin/rewrite_openfoam_paths.sh \
  && rewrite_openfoam_paths.sh /opt/openfoam \
     "/build/openfoam/${DOCKER_OPENFOAM_BUILD}" /opt/openfoam \
  && rm -f /opt/openfoam/runtime-apt.txt \
  && test -f /opt/openfoam/etc/bashrc
