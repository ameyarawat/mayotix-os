# MAYOTIX OS Phase 4: Rust/Go Developer Image
# Extends the hardened base with Rust and Go toolchains.
# Maintains non-root user, minimal surface, and security linters.

FROM mayotix/devbox:dev-base as base

# Labels for container metadata
LABEL org.opencontainers.image.title="mayotix-dev-rust-go"
LABEL org.opencontainers.image.description="Rust and Go developer image for MAYOTIX OS"
LABEL org.opencontainers.image.version="4.0-alpha"
LABEL org.opencontainers.image.vendor="MAYOTIX OS Project"
LABEL org.opencontainers.image.source="https://github.com/mayotix-os/mayotix-os"

# Install Rust and Go toolchains
USER root
RUN dnf install -y \
    # Rust (via rustup, but we'll install the toolchain via dnf for simplicity in base image)
    # Actually, we'll install rustup and then install stable rust
    # Similarly for Go, we'll install the Go package from dnf (which may be older) or use official binary.
    # For consistency and latest, we'll use the official installers but note that we are in a container.
    # We'll install the packages available in Fedora: rust, cargo, golang
    rust \
    cargo \
    golang \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Ensure the PATH includes Cargo and Go binaries (they are in standard paths)
# No need to change PATH as /usr/bin and /usr/local/bin are already included.

# Switch back to non-root user
USER developer
WORKDIR /home/developer

# Default command
CMD ["/bin/bash"]