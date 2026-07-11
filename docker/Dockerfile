# syntax=docker/dockerfile:1.4
# OpenFOAM runtime image. Targets:
#   fresh  - FROM phynexis-build, populate /opt/openfoam
#   extend - FROM existing openfoam image, rsync updated install tree

ARG DOCKER_BUILD_IMAGE_NAME=phynexis-build
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH

FROM ${DOCKER_BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH} AS compile

ARG TARGETARCH
ARG NUM_JOBS=4
ARG OPENFOAM_VERSION=v2412
ARG OPENFOAM_BUILD_MODULES=0

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NUM_JOBS=${NUM_JOBS} \
    OPENFOAM_BUILD_MODULES=${OPENFOAM_BUILD_MODULES}

WORKDIR /build/openfoam
COPY . .

RUN --mount=type=cache,target=/cache/openfoam,id=openfoam-build-${TARGETARCH} \
  chmod +x docker/bake_openfoam.sh docker/stage_openfoam.sh scripts/build_openfoam.sh \
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

FROM extend-base AS extend

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY --from=compile /build/stage/openfoam /tmp/stage-openfoam
RUN rsync -a --delete /tmp/stage-openfoam/ /opt/openfoam/ \
  && find /opt/openfoam/etc -type f -print0 \
  | xargs -0 sed -i 's|/build/openfoam/build|/opt/openfoam|g' \
  && rm -rf /tmp/stage-openfoam \
  && test -f /opt/openfoam/etc/bashrc
