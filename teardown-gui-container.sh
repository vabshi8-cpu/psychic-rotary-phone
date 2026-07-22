#!/bin/bash
#
# Teardown script - Removes all GUI container components
#

set -e

red() { echo "\033[0;31m$1\033[0m"; }
green() { echo "\033[0;32m$1\033[0m"; }

echo "$(red '⚠️  This will remove the GUI container setup!')"
read -p "Are you sure? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping services..."
systemctl stop novnc-web.service vncserver@1.service cloudflare-gui-tunnel.service 2>/dev/null || true
systemctl disable novnc-web.service vncserver@1.service cloudflare-gui-tunnel.service 2>/dev/null || true

rm -f /etc/systemd/system/novnc-web.service \
      /etc/systemd/system/vncserver@.service \
      /etc/systemd/system/cloudflare-gui-tunnel.service
systemctl daemon-reload

echo "Removing packages..."
apt-get remove -y --purge \
    tigervnc-standalone-server tigervnc-common tigervnc-xorg-extension \
    xfce4 xfce4-goodies novnc python3-websockify \
    cloudflared || true
apt-get autoremove -y

echo "Cleaning up files..."
rm -rf /opt/gui-container /usr/share/novnc /etc/cloudflared
rm -rf ~/.vnc ~/.cloudflared

green "✅ Cleanup complete! GUI components removed."
