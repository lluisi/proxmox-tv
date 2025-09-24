#!/usr/bin/env bash
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  ca-certificates \
  gnupg
msg_ok "Installed Dependencies"

msg_info "Installing Docker Engine"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
msg_ok "Installed Docker Engine"

msg_info "Setting up IPTVnator"
FRONTEND_PORT=4333
BACKEND_PORT=7333
mkdir -p /opt/iptvnator

# Get container IP
IP=$(hostname -I | awk '{print $1}')

cat > /opt/iptvnator/compose.yml << EOF
services:
  backend:
    image: 4gray/iptvnator-backend:latest
    restart: unless-stopped
    ports:
      - "${BACKEND_PORT}:3000"
    environment:
      - CLIENT_URL=http://${IP}:${FRONTEND_PORT}

  frontend:
    image: 4gray/iptvnator:latest
    restart: unless-stopped
    ports:
      - "${FRONTEND_PORT}:80"
    environment:
      - BACKEND_URL=http://${IP}:${BACKEND_PORT}
EOF

msg_info "Pulling Docker Images"
$STD docker compose -f /opt/iptvnator/compose.yml pull
msg_ok "Docker Images Pulled"

msg_info "Starting IPTVnator Stack"
$STD docker compose -f /opt/iptvnator/compose.yml up -d
msg_ok "IPTVnator Stack Started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_ok "Installation Complete!"
echo ""
echo "IPTVnator Access Information:"
echo "Frontend: http://${IP}:${FRONTEND_PORT}"
echo "Backend:  http://${IP}:${BACKEND_PORT}"