# OpenFOAM runtime image from linux dist-native (bundled libs).
# Build context of-dist must contain openfoam-native.tar.gz.

ARG DOCKER_UBUNTU_IMAGE_NAME=phynexis-ubuntu
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH

FROM ${DOCKER_UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}

ARG APT_MIRROR=

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

COPY docker/apt_setup.sh /usr/local/bin/apt_setup.sh
COPY scripts/rewrite_openfoam_paths.sh /usr/local/bin/rewrite_openfoam_paths.sh
COPY scripts/rewrite_openfoam_prefs.sh /usr/local/bin/rewrite_openfoam_prefs.sh
COPY scripts/openfoam_mpi_env.sh /usr/local/bin/openfoam_mpi_env.sh
COPY scripts/install_bundled_mpi_wrappers.sh /usr/local/bin/install_bundled_mpi_wrappers.sh
RUN chmod +x /usr/local/bin/apt_setup.sh \
    /usr/local/bin/rewrite_openfoam_paths.sh \
    /usr/local/bin/rewrite_openfoam_prefs.sh \
    /usr/local/bin/install_bundled_mpi_wrappers.sh \
  && APT_MIRROR=${APT_MIRROR} apt_setup.sh \
  && apt-get install -y --no-install-recommends ca-certificates openssh-client \
  && rm -rf /var/lib/apt/lists/*

COPY --from=of-dist openfoam-native.tar.gz /tmp/openfoam-native.tar.gz
RUN mkdir -p /opt/openfoam \
  && tar xzf /tmp/openfoam-native.tar.gz -C /opt/openfoam \
  && rm -f /tmp/openfoam-native.tar.gz \
  && test -f /opt/openfoam/.pack-source-prefix \
  && OLD_PREFIX="$(cat /opt/openfoam/.pack-source-prefix)" \
  && rewrite_openfoam_paths.sh /opt/openfoam "${OLD_PREFIX}" /opt/openfoam \
  && rewrite_openfoam_prefs.sh /opt/openfoam \
  && if [ -d /opt/openfoam/lib/bundled/mpi-bin ]; then \
       install_bundled_mpi_wrappers.sh /opt/openfoam/lib/bundled; \
     fi \
  && printf '%s\n' /opt/openfoam > /opt/openfoam/.pack-source-prefix \
  && test -f /opt/openfoam/etc/bashrc
