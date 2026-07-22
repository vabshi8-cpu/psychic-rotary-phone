#!/bin/bash
#
# ╔══════════════════════════════════════════════════════════════╗
# ║  Ubuntu 24.04 GUI Container Setup with Cloudflare Tunnel   ║
# ║  Version: 2.0.0 | License: MIT                             ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================

SCRIPT_VERSION="2.0.0"
VNC_PORT="5901"
NOVNC_PORT="6080"
VNC_DISPLAY=":1"
VNC_RESOLUTION="1280x720"
VNC_DEPTH="24"
DESKTOP_ENV="xfce4"
INSTALL_DIR="/opt/gui-container"
LOG_FILE="/var/log/gui-container-setup.log"
SERVICE_USER="${USER:-root}"

USE_QUICK_TUNNEL="false"
CUSTOM_DOMAIN=""
TUNNEL_NAME="gui-container-tunnel"

# Parse arguments
while [[ "#" -gt 0 ]]; do
    case "$1" in
        --quick-tunnel)
            USE_QUICK_TUNNEL="true"
            shift
            ;;
        --domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        --resolution)
            VNC_RESOLUTION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --quick-tunnel      Use Cloudflare quick tunnel (no domain needed)"
            echo "  --domain DOMAIN     Use custom domain with Cloudflare tunnel"
            echo "  --resolution RES     Set VNC resolution (default: 1280x720)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color functions
red() { echo "\033[0;31m$1\033[0m"; }
green() { echo "\033[0;32m$1\033[0m"; }
yellow() { echo "\033[0;33m$1\033[0m"; }
cyan() { echo "\033[0;36m$1\033[0m"; }

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }
log_success() { echo "✓ [SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }
log_error() { echo "✗ [ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }
log_warning() { echo "⚠ [WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

# ============================================
# SYSTEM RESOURCE DETECTION
# ============================================
detect_system_resources() {
    log_info "Detecting system resources..."
    
    # Detect CPU cores
    CPU_CORES=$(nproc)
    log_success "CPU Cores detected: $CPU_CORES"
    
    # Detect total RAM in GB
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    log_success "Total RAM detected: ${TOTAL_RAM_MB}MB (${TOTAL_RAM_GB}GB)"
    
    # Detect available disk space in GB
    DISK_AVAIL_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    DISK_TOTAL_GB=$(df -BG / | awk 'NR==2{print $2}' | tr -d 'G')
    log_success "Disk Space - Total: ${DISK_TOTAL_GB}GB, Available: ${DISK_AVAIL_GB}GB"
    
    # Detect architecture
    ARCH=$(uname -m)
    log_success "Architecture: $ARCH"
    
    # Validate minimum requirements
    if [[ $TOTAL_RAM_MB -lt 2048 ]]; then
        log_error "Insufficient RAM! Minimum required: 2GB (Detected: ${TOTAL_RAM_MB}MB)"
        log_warning "Installation may fail or perform poorly..."
    fi
    
    if [[ $DISK_AVAIL_GB -lt 10 ]]; then
        log_error "Insufficient disk space! Minimum required: 10GB (Available: ${DISK_AVAIL_GB}GB)"
        exit 1
    fi
    
    # Optimize based on resources
    MAKE_JOBS=$CPU_CORES
    if [[ $TOTAL_RAM_MB -lt 4096 ]]; then
        MAKE_JOBS=$((CPU_CORES / 2))
        log_warning "Low RAM detected, reducing parallel jobs to $MAKE_JOBS"
    fi
    
    log_success "Resource detection complete!"
    echo ""
}

# ============================================
# PREREQUISITES CHECK
# ============================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check OS version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_info "Detected OS: $PRETTY_NAME"
        if [[ "$VERSION_ID" != "24.04" ]]; then
            log_warning "Optimized for Ubuntu 24.04 (detected: $VERSION_ID)"
        fi
    fi
    
    log_success "Prerequisites check passed!"
    echo ""
}

# ============================================
# INSTALL DESKTOP ENVIRONMENT
# ============================================
install_desktop_environment() {
    log_info "Installing $DESKTOP_ENV desktop environment..."
    
    # Update package lists
    apt-get update -y
    
    # Install XFCE4 desktop environment (lightweight)
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        xfce4 \
        xfce4-goodies \
        dbus-x11 \
        x11-xserver-utils \
        xterm \
        firefox \
        nautilus \
        gnome-terminal \
        vim \
        git \
        curl \
        wget \
        htop \
        net-tools
    
    log_success "Desktop environment installed successfully!"
    echo ""
}

# ============================================
# INSTALL AND CONFIGURE VNC SERVER
# ============================================
install_vnc_server() {
    log_info "Installing TigerVNC server..."
    
    # Install TigerVNC
    apt-get install -y \
        tigervnc-standalone-server \
        tigervnc-common \
        tigervnc-xorg-extension
    
    log_success "TigerVNC installed!"
    
    # Create VNC directory structure
    mkdir -p /home/$SERVICE_USER/.vnc
    chown -R $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER/.vnc
    
    # Generate random VNC password
    VNC_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    
    # Set VNC password
    if [[ "$SERVICE_USER" != "root" ]]; then
        su - $SERVICE_USER -c "echo '$VNC_PASSWORD' | vncpasswd -f > /home/$SERVICE_USER/.vnc/passwd"
    else
        echo "$VNC_PASSWORD" | vncpasswd -f > /root/.vnc/passwd
    fi
    
    chmod 600 /home/$SERVICE_USER/.vnc/passwd
    
    # Create VNC startup script
    cat > /home/$SERVICE_USER/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR=/run/user/$(id -u)
exec startxfce4
EOF
    
    chmod +x /home/$SERVICE_USER/.vnc/xstartup
    chown -R $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER/.vnc/
    
    # Save credentials for display
    echo "$VNC_PASSWORD" > "$INSTALL_DIR/vnc_password.txt"
    chmod 600 "$INSTALL_DIR/vnc_password.txt"
    
    log_success "VNC server configured!"
    cyan "========================================"
    cyan "  VNC PASSWORD: $VNC_PASSWORD"
    cyan "  Port: $VNC_PORT | Display: $VNC_DISPLAY"
    cyan "========================================"
    echo ""
}

# ============================================
# INSTALL noVNC (WEB CLIENT)
# ============================================
install_novnc() {
    log_info "Installing noVNC web client..."
    
    # Install dependencies
    apt-get install -y \
        python3-websockify \
        python3-numpy \
        novnc
    
    # Download latest noVNC if not installed via package
    if [[ ! -d /usr/share/novnc ]]; then
        NOVNC_VERSION="v1.4.0"
        cd /tmp
        wget -q https://github.com/novnc/noVNC/archive/refs/tags/$NOVNC_VERSION.tar.gz
        tar -xzf $NOVNC_VERSION.tar.gz
        mv noVNC-${NOVNC_VERSION#v} /usr/share/novnc
        rm -f $NOVNC_VERSION.tar.gz
        
        # Download websockify
        wget -q https://github.com/novnc/websockify/archive/refs/tags/v0.11.0.tar.gz
        tar -xzf v0.11.0.tar.gz
        mv websockify-0.11.0 /usr/share/novnc/utils/websockify
        rm -f v0.11.0.tar.gz
    fi
    
    log_success "noVNC installed at /usr/share/novnc"
    log_success "Web interface will be available at port $NOVNC_PORT"
    echo ""
}

# ============================================
# SETUP CLOUDFLARE TUNNEL
# ============================================
setup_cloudflare_tunnel() {
    log_info "Setting up Cloudflare Tunnel..."
    
    # Install cloudflared
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update && apt-get install -y cloudflared
    
    log_success "cloudflared installed!"
    
    if [[ "$USE_QUICK_TUNNEL" == "true" ]]; then
        setup_quick_tunnel
    elif [[ -n "$CUSTOM_DOMAIN" ]]; then
        setup_named_tunnel
    else
        log_warning "No tunnel mode specified. Access locally at http://localhost:$NOVNC_PORT"
        return
    fi
    
    echo ""
}

setup_quick_tunnel() {
    log_info "Creating quick tunnel (temporary URL)..."
    
    # Create systemd service for quick tunnel
    cat > /etc/systemd/system/cloudflare-gui-tunnel.service << EOF
[Unit]
Description=Cloudflare Quick Tunnel for GUI Container
After=network.target

[Service
