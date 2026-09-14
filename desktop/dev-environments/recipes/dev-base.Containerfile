# MAYOTIX OS Phase 4: Hardened Base Developer Image
# Minimal, secure foundation for development containers.
# Uses non-root user by default, minimal package set, and pre-installed security linters.

FROM fedora:40

# Labels for container metadata
LABEL org.opencontainers.image.title="mayotix-dev-base"
LABEL org.opencontainers.image.description="Hardened base developer image for MAYOTIX OS"
LABEL org.opencontainers.image.version="4.0-alpha"
LABEL org.opencontainers.image.vendor="MAYOTIX OS Project"
LABEL org.opencontainers.image.source="https://github.com/mayotix-os/mayotix-os"

# Set environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Create non-root user (uid 1000 matches host user for seamless file ownership)
RUN groupadd -r developer --gid=1000 && \
    useradd -r -g developer --uid=1000 --create-home --shell /bin/bash developer && \
    mkdir -p /home/developer/Projects && \
    chown -R developer:developer /home/developer

# Install minimal essential packages + security tooling
RUN dnf install -y \
    # Shell & basic utils
    bash \
    coreutils \
    findutils \
    grep \
    gawk \
    sed \
    tar \
    gzip \
    bzip2 \
    xz \
    util-linux \
    # Development basics
    make \
    gcc \
    gcc-c++ \
    glibc-devel \
    # Version control
    git \
    # Security & linting tools (pre-installed for dev environments)
    shellcheck \
    hadolint \
    # Container/image tools (for nested container safety)
    podman \
    buildah \
    skopeo \
    # Trivy for vulnerability scanning (aligns with Phase 2)
    trivy \
    # Audit & monitoring
    audit \
    # Clean up
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Switch to non-root user by default
USER developer
WORKDIR /home/developer

# Default command
CMD ["/bin/bash"]

# Healthcheck (optional)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD /bin/true || exit 1