#!/bin/bash

# Simple Debian 12 Container Creation Script
# Usage: ./create-debian-ct.sh [container-id]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Get container ID
CTID="${1:-$(pvesh get /cluster/nextid)}"

# Settings
HOSTNAME="iptvnator"
MEMORY="2048"
CORES="1"
DISK="15"
BRIDGE="vmbr0"

echo -e "${GREEN}"
echo "============================================"
echo "  Debian 12 Container Creation"
echo "============================================"
echo -e "${NC}"
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "Memory: ${MEMORY}MB"
echo "CPU Cores: $CORES"
echo "Disk: ${DISK}GB"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
fi

# Check if container ID already exists
if pct status $CTID &>/dev/null; then
    msg_error "Container $CTID already exists"
fi

# Find any available Debian 12 template
msg_info "Looking for Debian 12 template..."
TEMPLATE=""

# Check local templates first
LOCAL_TEMPLATES=$(pveam list local 2>/dev/null | grep -E "debian-12.*\.tar\.(gz|zst|xz)" || true)
if [ -n "$LOCAL_TEMPLATES" ]; then
    TEMPLATE=$(echo "$LOCAL_TEMPLATES" | head -n1 | rev | cut -d'/' -f1 | rev)
    STORAGE="local"
    msg_ok "Found local template: $TEMPLATE"
else
    # Try other storage locations
    for storage in $(pvesm status -content vztmpl | awk 'NR>1 {print $1}'); do
        TEMPLATES=$(pveam list $storage 2>/dev/null | grep -E "debian-12.*\.tar\.(gz|zst|xz)" || true)
        if [ -n "$TEMPLATES" ]; then
            TEMPLATE=$(echo "$TEMPLATES" | head -n1 | rev | cut -d'/' -f1 | rev)
            STORAGE="$storage"
            msg_ok "Found template in $storage: $TEMPLATE"
            break
        fi
    done
fi

# If no template found, try to download one
if [ -z "$TEMPLATE" ]; then
    msg_info "No local template found, trying to download..."

    # Find storage that supports templates
    STORAGE=$(pvesm status -content vztmpl | awk 'NR>1 {print $1; exit}')
    if [ -z "$STORAGE" ]; then
        msg_error "No storage found that supports templates"
    fi

    # Try to download a simple Debian 12 template
    AVAILABLE=$(pveam available | grep -E "debian-12-standard.*\.tar\.(gz|zst|xz)" | head -n1)
    if [ -n "$AVAILABLE" ]; then
        TEMPLATE_NAME=$(echo "$AVAILABLE" | awk '{print $2}')
        msg_info "Downloading $TEMPLATE_NAME to $STORAGE..."

        if pveam download "$STORAGE" "$TEMPLATE_NAME"; then
            TEMPLATE="$TEMPLATE_NAME"
            msg_ok "Template downloaded successfully"
        else
            msg_error "Failed to download template"
        fi
    else
        msg_error "No Debian 12 template available for download"
    fi
fi

# Find storage for container
CONTAINER_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
if [ -z "$CONTAINER_STORAGE" ]; then
    msg_error "No storage found for containers"
fi

msg_info "Using template storage: $STORAGE"
msg_info "Using container storage: $CONTAINER_STORAGE"

# Create the container
msg_info "Creating container $CTID..."
pct create $CTID \
    "${STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$HOSTNAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --rootfs "${CONTAINER_STORAGE}:${DISK}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --features "nesting=1,keyctl=1" \
    --unprivileged 1 \
    --onboot 1 \
    --start 0

msg_ok "Container $CTID created successfully"

# Start the container
msg_info "Starting container..."
pct start $CTID

# Wait for network
msg_info "Waiting for network..."
sleep 10

for i in {1..30}; do
    if pct exec $CTID -- ip addr show eth0 | grep -q "inet "; then
        break
    fi
    sleep 2
done

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
msg_ok "Container started with IP: $IP"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Container Created Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Container ID: $CTID"
echo "IP Address: $IP"
echo ""
echo "Next step: Run the IPTVnator installation:"
echo "  ./install-iptvnator.sh $CTID"
echo ""