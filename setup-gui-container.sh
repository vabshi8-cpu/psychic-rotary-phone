#!/bin/bash
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║  Ubuntu 24.04 GUI Container Setup v2.0      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "❌ Run with sudo: sudo $0 --quick-tunnel"
    exit 1
fi

VNC_PORT="5901"
NOVNC_PORT="6080"
VNC_RESOLUTION="1280x720"
INSTALL_DIR="/opt/gui-container"
QUICK_TUNNEL=0

for arg in "$@"; do
    case "$arg" in
        --quick-tunnel) QUICK_TUNNEL=1 ;;
        --resolution=*) VNC_RESOLUTION="${arg#*=}" ;;
    esac
done

echo "📊 Detecting resources..."
CPU_CORES=$(nproc)
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
echo "   CPU: $CPU_CORES cores | RAM: ${RAM_MB}MB | Disk: ${DISK_GB}GB free"

if [[ "$DISK_GB" -lt 10 ]]; then echo "❌ Need 10GB+ disk"; exit 1; fi

echo "📦 Installing desktop..."
apt-get update -y > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies dbus-x11 firefox gnome-terminal vim curl wget htop tigervnc-standalone-server tigervnc-common python3-websockify novnc > /dev/null 2>&1
echo "✅ Desktop installed!"

echo "🔐 Setting up VNC..."
mkdir -p ~/.vnc
PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
echo "$PASS" | vncpasswd -f > ~/.vnc/passwd && chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER unset DBUS_SESSION_BUS_ADDRESS exec startxfce4
EOF
chmod +x ~/.vnc/xstartup

mkdir -p "$INSTALL_DIR" && echo "$PASS" > "$INSTALL_DIR/pass.txt"
echo "🔐 VNC Password: $PASS"

if [[ "$QUICK_TUNNEL" -eq 1 ]]; then
    echo "☁️  Starting Cloudflare Tunnel..."
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y > /dev/null 2>&1 && apt-get install -y cloudflared > /dev/null 2>&1
    nohup cloudflared tunnel --url http://localhost:$NOVNC_PORT > /tmp/cf.log 2>&1 &
    sleep 10
    URL=$(grep -oE 'https://[^ ]+trycloudflare\.com' /tmp/cf.log | tail -1)
    if [[ -n "$URL" ]]; then
        echo "$URL" > "$INSTALL_DIR/url.txt"
        echo ""
        echo "╔════════════════════════════════╗"
        echo "║  🌐 $URL ║"
        echo "╚════════════════════════════════╝"
    fi
fi

echo "🚀 Starting services..."
vncserver :1 -geometry $VNC_RESOLUTION -depth 24 -localhost no 2>/dev/null || { vncserver -kill :1 2>/dev/null; vncserver :1 -geometry $VNC_RESOLUTION -depth 24 -localhost no; }
sleep 2
nohup /usr/share/novnc/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NOVNC_PORT > /dev/null 2>&1 &
sleep 3

echo ""
echo "✅ DONE!"
echo "   Local: http://localhost:$NOVNC_PORT"
[[ -f "$INSTALL_DIR/url.txt" ]] && echo "   Public: $(cat $INSTALL_DIR/url.txt)"
echo "   Pass: cat $INSTALL_DIR/pass.txt"
