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
var_install="iptvnator-install"  # This tells the framework what install script to look for

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
description

msg_ok "Completed Successfully!\n"