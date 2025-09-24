#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/4gray/iptvnator

APP="IPTVnator"
var_tags="${var_tags:-media;iptv;player}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-15}"
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
description

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function build_container() {
  show_checkmark "LXC Build"
  if pct status $CTID &>/dev/null; then
    pct destroy $CTID
  fi

  DISK_REF="$DISK_SIZE"
  if [ "$DISK_REF" == "" ]; then
    DISK_SIZE="2"
    DISK_REF="2G"
  else
    DISK_REF="${DISK_SIZE}G"
  fi

  if [ "$CT_TYPE" == "1" ]; then
    FEATURES="nesting=1,keyctl=1"
  else
    FEATURES="nesting=1"
  fi

  TEMP_DIR=$(mktemp -d)
  pushd $TEMP_DIR >/dev/null

  export CTID CT_TYPE PW CT_TEMPLATE DISK_SIZE CORE_COUNT RAM_SIZE BRG NET GATE APT_CACHER APT_CACHER_IP DISABLEIP6 MTU SD NS MAC VLAN SSH
  export FEATURES HN DISK_REF

  bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/create_lxc.sh)" || exit

  IP=$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  pct set $CTID -description "# ${APP}

  ${APP} is installed and ready to use.

  **Default Network Configuration**

  - **IP Address:** ${IP}
  - **Username:** N/A
  - **Password:** N/A"
  popd >/dev/null
  rm -rf $TEMP_DIR

  # Custom installation instead of calling external script
  lxc-attach -n "$CTID" -- bash << 'EOF'
msg_info() { echo -e "\033[38;5;2m[INFO]\033[0m $1"; }
msg_ok() { echo -e "\033[38;5;2m[✔️ ]\033[0m $1"; }
msg_error() { echo -e "\033[38;5;1m[ERROR]\033[0m $1"; }

msg_info "Installing Docker Engine & Compose"
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
$(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker >/dev/null 2>&1
msg_ok "Docker Installed"

FRONTEND_PORT=4333
BACKEND_PORT=7333
IP=$(hostname -I | awk '{print $1}')

msg_info "Deploying IPTVnator (frontend:${FRONTEND_PORT} backend:${BACKEND_PORT})"
mkdir -p /opt/iptvnator
cat > /opt/iptvnator/compose.yml << COMPOSE_EOF
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
COMPOSE_EOF

docker compose -f /opt/iptvnator/compose.yml pull
docker compose -f /opt/iptvnator/compose.yml up -d
msg_ok "IPTVnator stack is up"

msg_ok "Completed Successfully!"
echo -e "\033[38;5;2mIPTVnator setup has been successfully initialized!\033[0m"
echo -e "\033[33m Access it using the following URL:\033[0m"
echo -e "\033[1mhttp://${IP}:${FRONTEND_PORT}\033[0m"
echo -e "\033[33m Backend endpoint (for reference):\033[0m"
echo -e "\033[1mhttp://${IP}:${BACKEND_PORT}\033[0m"
EOF
}

default_settings
build_container