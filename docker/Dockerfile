# OpenFOAM runtime image from linux dist-native (bundled libs).
# Build context of-dist must contain phynexis-foam.tar.gz.

ARG DOCKER_UBUNTU_IMAGE_NAME=phynexis-ubuntu
ARG UBUNTU_VERSION=24.04
ARG TARGETARCH

FROM ${DOCKER_UBUNTU_IMAGE_NAME}:${UBUNTU_VERSION}-${TARGETARCH}

ARG APT_MIRROR=

# Runtime PATH / bundled mpi-bin come from /root/.bashrc (and entrypoint),
# not from ENV here. Do not patch OpenFOAM etc/bashrc.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    OPENFOAM_PREFIX=/opt/openfoam \
    HOME=/root

COPY docker/apt_setup.sh /usr/local/bin/apt_setup.sh
COPY scripts/rewrite_openfoam_paths.sh /usr/local/bin/rewrite_openfoam_paths.sh
COPY scripts/rewrite_openfoam_prefs.sh /usr/local/bin/rewrite_openfoam_prefs.sh
COPY scripts/install_dist_bashrc.sh /usr/local/bin/install_dist_bashrc.sh
COPY scripts/etc/bashrc /usr/local/share/openfoam/etc/bashrc
COPY scripts/openfoam_mpi_env.sh /usr/local/bin/openfoam_mpi_env.sh
COPY scripts/install_bundled_mpi_wrappers.sh /usr/local/bin/install_bundled_mpi_wrappers.sh
RUN chmod +x /usr/local/bin/apt_setup.sh \
    /usr/local/bin/rewrite_openfoam_paths.sh \
    /usr/local/bin/rewrite_openfoam_prefs.sh \
    /usr/local/bin/install_dist_bashrc.sh \
    /usr/local/bin/install_bundled_mpi_wrappers.sh \
  && APT_MIRROR=${APT_MIRROR} apt_setup.sh \
  && apt-get install -y --no-install-recommends ca-certificates openssh-client \
  && rm -rf /var/lib/apt/lists/*

COPY --from=of-dist phynexis-foam.tar.gz /tmp/phynexis-foam.tar.gz
RUN mkdir -p /opt/openfoam \
  && tar xzf /tmp/phynexis-foam.tar.gz -C /opt/openfoam \
  && rm -f /tmp/phynexis-foam.tar.gz \
  && test -f /opt/openfoam/.pack-source-prefix \
  && test -f /opt/openfoam/openfoam/etc/bashrc \
  && OLD_PREFIX="$(cat /opt/openfoam/.pack-source-prefix)" \
  && rewrite_openfoam_paths.sh /opt/openfoam/openfoam "${OLD_PREFIX}" /opt/openfoam \
  && rewrite_openfoam_prefs.sh /opt/openfoam/openfoam \
  && install_dist_bashrc.sh /opt/openfoam \
  && if [ -d /opt/openfoam/openfoam/lib/mpi-bin ]; then \
       install_bundled_mpi_wrappers.sh /opt/openfoam/openfoam/lib; \
     fi \
  && printf '%s\n' /opt/openfoam > /opt/openfoam/.pack-source-prefix \
  && test -f /opt/openfoam/etc/bashrc \
  && test -f /opt/openfoam/openfoam/etc/bashrc

COPY docker/root.bashrc /root/.bashrc
COPY docker/entrypoint.sh /usr/local/bin/openfoam-entrypoint
RUN chmod +x /usr/local/bin/openfoam-entrypoint

ENTRYPOINT ["/usr/local/bin/openfoam-entrypoint"]
CMD ["bash"]
