FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_RESOLUTION=1280x720

# Install prerequisites
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    wget \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Copy and run setup script
COPY setup-gui-container.sh /opt/setup.sh
RUN chmod +x /opt/setup.sh

# Expose ports
EXPOSE 6080 5901

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:6080/ || exit 1

# Start services
CMD ["/opt/setup.sh", "--quick-tunnel"] && tail -f /dev/null
