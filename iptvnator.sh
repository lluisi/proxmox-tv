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

# Store original build_container function and override
original_build_container=$(declare -f build_container)
unset -f build_container

function build_container() {
  # Call most of the original build_container but replace the install script execution
  if [ "$VERB" == "yes" ]; then set -x; fi

  if [ "$CT_TYPE" == "1" ]; then
    FEATURES="keyctl=1,nesting=1"
  else
    FEATURES="nesting=1"
  fi

  TEMP_DIR=$(mktemp -d)
  pushd $TEMP_DIR >/dev/null

  # Export functions file path for the install script
  if [[ "$var_os" == "alpine" ]]; then
    export FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/alpine-install.func)"
  else
    export FUNCTIONS_FILE_PATH="$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)"
  fi

  # Export required variables
  export tz
  if [[ "$var_os" == "ubuntu" ]]; then
    export ST="sudo"
  fi
  export DISABLEIPV6="$DISABLEIP6"
  export APPLICATION="$APP"
  export app="$NSAPP"
  export PASSWORD="$PW"
  export VERBOSE="$VERB"
  export SSH_ROOT="${SSH}"
  export CTID="$CT_ID"
  export CTTYPE="$CT_TYPE"
  export PCT_OSTYPE="$var_os"
  export PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export PCT_OPTIONS="
    -features $FEATURES
    -hostname $HN
    ${SD:+-description "$SD"}
    ${NS:+-nameserver "$NS"}
    ${BRIDGE:+-net0 name=eth0,bridge="$BRIDGE"${VLAN:+,tag="$VLAN"}${MAC:+,hwaddr="$MAC"},ip=$NET${GATE:+,gw="$GATE"}${MTU:+,mtu="$MTU"}}
    ${NETSNIFF:+-net1 name=eth1,bridge="$NETSNIFF",ip=$NETIP,mtu="$NETMTU"}
    -onboot 1
    -cores $CORE_COUNT
    -memory $RAM_SIZE
    -unprivileged $CT_TYPE
    ${PW:+-password $PW}
    ${MOUNT:+-mp0 "$MOUNT,mp=/mnt/host"}
  "

  # Create LXC container
  msg_info "Creating LXC Container"
  bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/create_lxc.sh)" || exit
  msg_ok "LXC Container Created"

  # Check if container is running
  msg_info "Starting LXC Container"
  pct start "$CT_ID"
  sleep 5

  # Wait for network
  msg_info "Waiting for container network"
  max_attempts=30
  attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if pct exec "$CT_ID" -- ip a s dev eth0 2>/dev/null | grep -q inet; then
      break
    fi
    sleep 2
    ((attempt++))
  done
  msg_ok "Network Ready"

  # Get IP address
  IP=$(pct exec "$CT_ID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

  # Configure container description
  pct set "$CT_ID" -description "# ${APP} LXC
### https://github.com/4gray/iptvnator

Frontend: http://${IP}:4333
Backend: http://${IP}:7333"

  # Install IPTVnator using our custom install script
  msg_info "Installing ${APP}"
  pct exec "$CT_ID" -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/lluisi/proxmox-tv/main/iptvnator-install.sh)" || exit
  msg_ok "${APP} Installed"

  popd >/dev/null
  rm -rf $TEMP_DIR

  # Final success message with IP
  msg_ok "Installation Complete!"
  echo ""
  msg_info "IPTVnator Access Information:"
  echo -e "Frontend: ${BGN}http://${IP}:4333${CL}"
  echo -e "Backend:  ${BGN}http://${IP}:7333${CL}"
  echo ""
}

# Now call build_container
build_container