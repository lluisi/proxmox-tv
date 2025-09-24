#!/usr/bin/env bash

# IPTVnator Proxmox LXC Installation Script (Standalone)
# This script creates an LXC container and installs IPTVnator without relying on community-scripts framework

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Default settings
APP="IPTVnator"
CTID="${1:-$(pvesh get /cluster/nextid)}"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
DISK_SIZE="15"
CPU_CORES="1"
RAM_SIZE="2048"
HOSTNAME="iptvnator"
BRIDGE="vmbr0"

# Header
clear
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║                     IPTVnator LXC Installer                     ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

msg_info "Container Settings:"
echo "  • Container ID: $CTID"
echo "  • Template: Debian 12"
echo "  • Disk: ${DISK_SIZE}GB"
echo "  • CPU: ${CPU_CORES} cores"
echo "  • RAM: ${RAM_SIZE}MB"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
fi

# Get storage location
STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1}' | head -n1)
if [ -z "$STORAGE" ]; then
    msg_error "No suitable storage found"
fi
msg_ok "Using storage: $STORAGE"

# Download template if needed
msg_info "Checking template..."
if ! pveam list $STORAGE | grep -q "$TEMPLATE"; then
    msg_info "Downloading Debian 12 template..."
    pveam download $STORAGE $TEMPLATE
fi
msg_ok "Template ready"

# Create container
msg_info "Creating LXC container..."
pct create $CTID ${STORAGE}:vztmpl/${TEMPLATE} \
    --hostname $HOSTNAME \
    --cores $CPU_CORES \
    --memory $RAM_SIZE \
    --rootfs ${STORAGE}:${DISK_SIZE} \
    --net0 name=eth0,bridge=${BRIDGE},ip=dhcp \
    --features nesting=1,keyctl=1 \
    --unprivileged 1 \
    --onboot 1 \
    --start 0

msg_ok "Container created"

# Start container
msg_info "Starting container..."
pct start $CTID
sleep 5

# Wait for network
msg_info "Waiting for network..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if pct exec $CTID -- ip a s dev eth0 2>/dev/null | grep -q "inet "; then
        break
    fi
    sleep 2
    ((attempt++))
done

if [ $attempt -eq $max_attempts ]; then
    msg_error "Network timeout"
fi
msg_ok "Network ready"

# Get IP
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
msg_ok "Container IP: $IP"

# Update container
msg_info "Updating container OS..."
pct exec $CTID -- bash -c "apt-get update && apt-get upgrade -y"

# Install Docker
msg_info "Installing Docker..."
pct exec $CTID -- bash -c "
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
"
msg_ok "Docker installed"

# Setup IPTVnator
msg_info "Setting up IPTVnator..."
pct exec $CTID -- bash -c "
mkdir -p /opt/iptvnator
cat > /opt/iptvnator/compose.yml << 'EOF'
services:
  backend:
    image: 4gray/iptvnator-backend:latest
    restart: unless-stopped
    ports:
      - '7333:3000'
    environment:
      - CLIENT_URL=http://${IP}:4333

  frontend:
    image: 4gray/iptvnator:latest
    restart: unless-stopped
    ports:
      - '4333:80'
    environment:
      - BACKEND_URL=http://${IP}:7333
EOF
"
msg_ok "IPTVnator configured"

# Pull and start containers
msg_info "Starting IPTVnator services..."
pct exec $CTID -- bash -c "cd /opt/iptvnator && docker compose pull && docker compose up -d"
msg_ok "IPTVnator services started"

# Set description
pct set $CTID -description "# IPTVnator LXC
### https://github.com/4gray/iptvnator

Frontend: http://${IP}:4333
Backend: http://${IP}:7333"

# Success message
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Installation Complete!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Access IPTVnator:${NC}"
echo -e "  Frontend: ${GREEN}http://${IP}:4333${NC}"
echo -e "  Backend:  ${GREEN}http://${IP}:7333${NC}"
echo ""
echo -e "${BLUE}Container ID: ${CTID}${NC}"
echo ""