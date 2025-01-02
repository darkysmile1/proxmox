#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# App default values
APP="TeddyCloud"
var_tags="media"
var_cpu="2"
var_disk="8"
var_ram="1024"
var_os="debian"
var_version="12"
CONTAINER_ID="190"
CONTAINER_NAME="teddycloud"
HOST_IP="192.168.178.190"

# App Output & Base Settings
header_info "${APP}"
base_settings

# Core Funktionen
variables
color
catch_errors

function build_teddycloud_container() {
    msg_info "Creating LXC container for ${APP} with IP ${HOST_IP}"
    
    # Container erstellen
    build_container \
        -id ${CONTAINER_ID} \
        -name ${CONTAINER_NAME} \
        -os ${var_os} \
        -version ${var_version} \
        -disk ${var_disk} \
        -ram ${var_ram} \
        -cpu ${var_cpu} \
        -net 0,bridge=vmbr0,ip=${HOST_IP}/24,gw=192.168.178.1 \
        -features nesting=1,keyctl=1 \
        -tags ${var_tags}

    if [[ $? -ne 0 ]]; then
        msg_error "Failed to create LXC container"
        exit 1
    fi

    msg_info "Starting LXC container for ${APP}"
    pct start ${CONTAINER_ID}
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to start LXC container"
        exit 1
    fi

    # Warte, bis der Container betriebsbereit ist
    sleep 5

    msg_ok "LXC container created and started successfully"
}


function setup_teddycloud() {
    msg_info "Installing Docker and setting up TeddyCloud"

    # Docker installieren
    pct exec ${CONTAINER_ID} -- bash -c "apt update && apt install -y docker.io docker-compose"

    # Docker-Compose-Setup erstellen
    pct exec ${CONTAINER_ID} -- bash -c "mkdir -p /opt/${APP}"
    cat <<EOF | pct exec ${CONTAINER_ID} -- bash -c "cat > /opt/${APP}/docker-compose.yml"
version: '3'
services:
  ${APP}:
    container_name: ${APP}
    hostname: ${APP}
    image: ghcr.io/toniebox-reverse-engineering/teddycloud:latest
    ports:
      - 80:80
      - 8443:8443
      - 443:443
    volumes:
      - certs:/teddycloud/certs
      - config:/teddycloud/config
      - content:/teddycloud/data/content
      - library:/teddycloud/data/library
      - firmware:/teddycloud/data/firmware
      - cache:/teddycloud/data/cache
    restart: unless-stopped
volumes:
  certs:
  config:
  content:
  library:
  firmware:
  cache:
EOF

    # TeddyCloud starten
    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/${APP} && docker-compose up -d"

    if [[ $? -ne 0 ]]; then
        msg_error "Failed to start TeddyCloud"
        exit 1
    fi

    msg_ok "${APP} is now running at http://${HOST_IP}"
}

# Startpunkt des Skripts
start
build_teddycloud_container
setup_teddycloud
description

msg_ok "Setup completed successfully!"
