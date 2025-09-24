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

# Get proper storage for templates (vztmpl) and containers (rootdir)
msg_info "Finding suitable storage..."

# Get template storage
TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 && /active/ {print $1}' | head -n1)
if [ -z "$TEMPLATE_STORAGE" ]; then
    TEMPLATE_STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1}' | head -n1)
fi

# Get container storage
CONTAINER_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 && /active/ {print $1}' | head -n1)
if [ -z "$CONTAINER_STORAGE" ]; then
    CONTAINER_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1}' | head -n1)
fi

if [ -z "$TEMPLATE_STORAGE" ]; then
    msg_error "No storage found for templates. Please check your storage configuration."
fi

if [ -z "$CONTAINER_STORAGE" ]; then
    msg_error "No storage found for containers. Please check your storage configuration."
fi

msg_ok "Template storage: $TEMPLATE_STORAGE"
msg_ok "Container storage: $CONTAINER_STORAGE"

# Update template list
msg_info "Updating template list..."
pveam update >/dev/null 2>&1

# Find available Debian 12 template
msg_info "Checking for Debian 12 templates..."
TEMPLATE=""

# Try to find local template first
LOCAL_TEMPLATE=$(pveam list $TEMPLATE_STORAGE 2>/dev/null | grep -E "debian-12.*\.tar\.(gz|zst|xz)" | head -n1)
if [ -n "$LOCAL_TEMPLATE" ]; then
    # Extract just the filename from the full path
    TEMPLATE=$(echo "$LOCAL_TEMPLATE" | sed "s|^${TEMPLATE_STORAGE}:vztmpl/||")
    msg_ok "Found local template: $TEMPLATE"
else
    # Find available template to download
    msg_info "Searching for Debian 12 template to download..."

    # First try to find the standard Debian 12 template from system section
    TEMPLATE_LINE=$(pveam available | grep -E "system.*debian-12-standard.*\.tar\.(gz|zst|xz)" | head -n1)

    if [ -z "$TEMPLATE_LINE" ]; then
        # Try any debian-12 standard template
        TEMPLATE_LINE=$(pveam available | grep -E "debian-12-standard.*\.tar\.(gz|zst|xz)" | head -n1)
    fi

    if [ -z "$TEMPLATE_LINE" ]; then
        # Fallback to debian-12 core template
        TEMPLATE_LINE=$(pveam available | grep -E "debian-12-turnkey-core.*\.tar\.(gz|zst|xz)" | head -n1)
    fi

    if [ -z "$TEMPLATE_LINE" ]; then
        msg_info "Available templates:"
        pveam available | grep debian-12 | head -5
        msg_error "No suitable Debian 12 template found. Please manually download using: pveam download $TEMPLATE_STORAGE <template-name>"
    fi

    # Extract section and template name
    SECTION=$(echo "$TEMPLATE_LINE" | awk '{print $1}')
    TEMPLATE_NAME=$(echo "$TEMPLATE_LINE" | awk '{print $2}')

    msg_info "Downloading template: $TEMPLATE_NAME from section: $SECTION"

    # Download the template
    if ! pveam download $TEMPLATE_STORAGE "$TEMPLATE_NAME" 2>/dev/null; then
        msg_info "Trying alternative download method..."
        # Some systems need the section prefix
        if ! pveam download $TEMPLATE_STORAGE "$SECTION:$TEMPLATE_NAME" 2>/dev/null; then
            # Last attempt without any prefix
            pveam download $TEMPLATE_STORAGE "$(basename $TEMPLATE_NAME)"
        fi
    fi

    # Verify download and get just the filename
    FULL_TEMPLATE=$(pveam list $TEMPLATE_STORAGE 2>/dev/null | grep -E "debian-12.*\.tar\.(gz|zst|xz)" | head -n1)
    if [ -z "$FULL_TEMPLATE" ]; then
        msg_error "Failed to download template. Please check your network and storage configuration."
    fi

    # Extract just the filename from the full path
    TEMPLATE=$(echo "$FULL_TEMPLATE" | sed "s|^${TEMPLATE_STORAGE}:vztmpl/||")
    msg_ok "Template ready: $TEMPLATE"
fi

# Create container
msg_info "Creating LXC container..."
pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} \
    --hostname $HOSTNAME \
    --cores $CPU_CORES \
    --memory $RAM_SIZE \
    --rootfs ${CONTAINER_STORAGE}:${DISK_SIZE} \
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
pct exec $CTID -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"

# Install Docker
msg_info "Installing Docker dependencies..."
pct exec $CTID -- bash -c "
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release
"

msg_info "Adding Docker repository..."
pct exec $CTID -- bash -c "
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable' > /etc/apt/sources.list.d/docker.list
"

msg_info "Installing Docker Engine..."
pct exec $CTID -- bash -c "
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
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
msg_info "Pulling Docker images (this may take a while)..."
pct exec $CTID -- bash -c "cd /opt/iptvnator && docker compose pull"
msg_ok "Docker images downloaded"

msg_info "Starting IPTVnator services..."
pct exec $CTID -- bash -c "cd /opt/iptvnator && docker compose up -d"
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