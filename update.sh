#!/bin/bash
 
set -euo pipefail
 
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }
error() { echo -e "${RED}[✘]${NC} $1"; }

INSTALL_PATH="/usr/bin/xmp"
SCRIPT_URL="https://raw.githubusercontent.com/XMPlusDev/XMPanel/refs/heads/main/xmp.sh"

# Check root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root."
  exit 1
fi

if systemctl is-active --quiet XMP.service 2>/dev/null; then
    systemctl stop XMP.service
fi
if systemctl is-enabled --quiet XMP.service 2>/dev/null; then
    systemctl disable XMP.service
fi
if [ -f "/etc/systemd/system/XMP.service" ]; then
    rm -f /etc/systemd/system/XMP.service
fi
systemctl daemon-reload

cat > /etc/systemd/system/XMP.service <<EOF
[Unit]
Description=XMPanel
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/XMPanel
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}==> Enabling and starting XMP service...${NC}"
systemctl daemon-reload
systemctl enable XMP.service
systemctl start XMP.service

# Remove existing XMPanel Script
if [[ -f "$INSTALL_PATH" ]]; then
  info "Removing existing XMPanel Script..."
  rm -rf "$INSTALL_PATH"
fi

# Download
info "Downloading XMPanel Script..."
curl -o "$INSTALL_PATH" -Ls "$SCRIPT_URL"
log "Downloaded to $INSTALL_PATH"

chmod +x "$INSTALL_PATH"

log "XMPanel Script installed successfully. Run with: xmp"