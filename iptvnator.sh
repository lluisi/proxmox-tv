#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/4gray/iptvnator

APP="IPTVnator"
var_tags="${var_tags:-media;iptv;player}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/iptvnator/compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating OS packages"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "OS Updated"

  msg_info "Updating Docker images and restarting stack"
  docker compose -f /opt/iptvnator/compose.yml pull
  docker compose -f /opt/iptvnator/compose.yml up -d
  msg_ok "${APP} Updated Successfully"
  exit
}

start
build_container
# (NO description aquí, per evitar el 404)

msg_info "Installing Docker Engine & Compose"
$STD apt-get update
$STD apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
$STD apt-get update
$STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker >/dev/null 2>&1
msg_ok "Docker Installed"

FRONTEND_PORT=4333
BACKEND_PORT=7333

msg_info "Deploying ${APP} (frontend:${FRONTEND_PORT} backend:${BACKEND_PORT})"
mkdir -p /opt/iptvnator
cat > /opt/iptvnator/compose.yml <<EOF
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

docker compose -f /opt/iptvnator/compose.yml pull
docker compose -f /opt/iptvnator/compose.yml up -d
msg_ok "${APP} stack is up"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${FRONTEND_PORT}${CL}"
echo -e "${INFO}${YW} Backend endpoint (for reference):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${BACKEND_PORT}${CL}"
