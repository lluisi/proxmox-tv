#!/bin/bash

# IPTVnator Installation Script
# Usage: ./install-iptvnator.sh [container-id]
# This script installs IPTVnator inside a Debian container

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
CTID="$1"

if [ -z "$CTID" ]; then
    msg_error "Usage: $0 <container-id>"
fi

echo -e "${GREEN}"
echo "============================================"
echo "  IPTVnator Installation"
echo "============================================"
echo -e "${NC}"
echo "Container ID: $CTID"
echo ""

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
fi

# Check if container exists and is running
if ! pct status $CTID &>/dev/null; then
    msg_error "Container $CTID does not exist"
fi

if [ "$(pct status $CTID)" != "status: running" ]; then
    msg_info "Starting container $CTID..."
    pct start $CTID
    sleep 5
fi

# Get container IP
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
msg_info "Container IP: $IP"

# Create installation script that will run inside the container
INSTALL_SCRIPT=$(cat << 'SCRIPT_EOF'
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }

msg_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
msg_ok "System updated"

msg_info "Installing dependencies..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common
msg_ok "Dependencies installed"

msg_info "Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
msg_ok "Docker repository added"

msg_info "Installing Docker..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable docker
systemctl start docker
msg_ok "Docker installed"

msg_info "Setting up IPTVnator..."
mkdir -p /opt/iptvnator

# Get container IP for configuration
CONTAINER_IP=$(hostname -I | awk '{print $1}')

# Create docker-compose.yml
cat > /opt/iptvnator/compose.yml << EOF
version: '3.8'
services:
  backend:
    image: 4gray/iptvnator-backend:latest
    restart: unless-stopped
    ports:
      - "7333:3000"
    environment:
      - CLIENT_URL=http://${CONTAINER_IP}:4333
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health" ]
      interval: 30s
      timeout: 10s
      retries: 3

  frontend:
    image: 4gray/iptvnator:latest
    restart: unless-stopped
    ports:
      - "4333:80"
    environment:
      - BACKEND_URL=http://${CONTAINER_IP}:7333
    depends_on:
      - backend
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost" ]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

msg_ok "Configuration created"

msg_info "Pulling Docker images..."
cd /opt/iptvnator
docker compose pull
msg_ok "Images pulled"

msg_info "Starting IPTVnator services..."
docker compose up -d
msg_ok "Services started"

# Wait for services to be ready
msg_info "Waiting for services to start..."
sleep 10

# Check if services are running
if docker compose ps | grep -q "Up"; then
    msg_ok "IPTVnator is running!"
else
    echo "Warning: Some services may not be running properly"
    docker compose ps
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  IPTVnator Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Access IPTVnator at:"
echo "  Frontend: http://${CONTAINER_IP}:4333"
echo "  Backend:  http://${CONTAINER_IP}:7333"
echo ""
echo "Container commands:"
echo "  docker compose -f /opt/iptvnator/compose.yml logs    # View logs"
echo "  docker compose -f /opt/iptvnator/compose.yml stop    # Stop services"
echo "  docker compose -f /opt/iptvnator/compose.yml start   # Start services"
echo ""

SCRIPT_EOF
)

# Execute the installation script inside the container
msg_info "Installing IPTVnator inside container..."
echo "$INSTALL_SCRIPT" | pct exec $CTID -- bash

# Set container description
pct set $CTID -description "# IPTVnator Container
### https://github.com/4gray/iptvnator

Frontend: http://${IP}:4333
Backend: http://${IP}:7333

Docker Compose: /opt/iptvnator/compose.yml"

msg_ok "Installation completed successfully!"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  IPTVnator Ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Container: $CTID"
echo "Frontend: http://$IP:4333"
echo "Backend:  http://$IP:7333"
echo ""
echo "To manage the services:"
echo "  pct exec $CTID -- docker compose -f /opt/iptvnator/compose.yml logs"
echo "  pct exec $CTID -- docker compose -f /opt/iptvnator/compose.yml restart"
echo ""