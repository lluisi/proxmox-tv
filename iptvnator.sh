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

# Override build_container function to use our custom install script
unset -f build_container
function build_container() {
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

  # Install IPTVnator using our custom install script
  msg_info "Installing ${APP}"
  lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/lluisi/proxmox-tv/main/iptvnator-install.sh)" || exit
  msg_ok "${APP} Installed"

  popd >/dev/null
  rm -rf $TEMP_DIR
}

description

msg_ok "Completed Successfully!\n"
echo -e "${APP} has been installed successfully!"
echo -e ""
echo -e "Access the frontend at: \033[1;32mhttp://<IP>:4333\033[0m"
echo -e "Backend endpoint: \033[1;32mhttp://<IP>:7333\033[0m"