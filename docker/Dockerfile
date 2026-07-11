# syntax=docker/dockerfile:1.4
# OpenFOAM runtime image: compile (cached) + fresh final stage.

ARG DOCKER_BUILD_IMAGE_NAME=phynexis-build
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
  && chmod +x docker/bake_openfoam.sh docker/stage_openfoam.sh scripts/build_openfoam.sh \
  && OPENFOAM_VERSION="${OPENFOAM_VERSION}" NUM_JOBS=${NUM_JOBS} \
     OPENFOAM_BUILD_MODULES="${OPENFOAM_BUILD_MODULES}" \
     ./docker/bake_openfoam.sh

FROM ${DOCKER_BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH} AS fresh

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY --from=compile /build/stage/openfoam /opt/openfoam
RUN find /opt/openfoam/etc -type f -print0 \
  | xargs -0 sed -i 's|/build/openfoam/build|/opt/openfoam|g' \
  && test -f /opt/openfoam/etc/bashrc
