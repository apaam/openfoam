ARG DOCKER_BUILD_IMAGE_NAME=phynexis-build
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH
FROM ${DOCKER_BUILD_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}

ARG TARGETARCH
ARG NUM_JOBS=4
ARG OPENFOAM_VERSION=v2412

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NUM_JOBS=${NUM_JOBS}

WORKDIR /build/openfoam-src
COPY . .

COPY docker/bake_openfoam.sh /usr/local/bin/bake_openfoam.sh
RUN --mount=type=cache,target=/cache/openfoam-src,id=openfoam-build-${TARGETARCH} \
  chmod +x /usr/local/bin/bake_openfoam.sh \
  && OPENFOAM_VERSION="${OPENFOAM_VERSION}" NUM_JOBS=${NUM_JOBS} /usr/local/bin/bake_openfoam.sh
