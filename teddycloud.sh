#!/usr/bin/env bash

APP="TeddyCloud"
CONTAINER_ID="190"
CONTAINER_NAME="teddycloud"
DOCKER_IMAGE="ghcr.io/toniebox-reverse-engineering/teddycloud:latest"
HOST_IP="192.168.178.190"
DISK_SIZE="8G"
RAM="1024"
CPU_CORES="2"
OS_TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
TEMPLATE_STORAGE="local:vztmpl"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

function msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

function msg_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

function msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prüfen, ob die nötigen Tools vorhanden sind
function check_requirements() {
    if ! command -v pct &>/dev/null; then
        msg_error "Proxmox pct tool not found. Please ensure you're running this on a Proxmox host."
        exit 1
    fi
}

# Vorlage überprüfen und herunterladen
function check_template() {
    msg_info "Checking if LXC template ${OS_TEMPLATE} exists"
    if ! pveam list | grep -q "${OS_TEMPLATE}"; then
        msg_info "Template not found, downloading ${OS_TEMPLATE}"
        pveam update
        pveam download local ${OS_TEMPLATE}
        if [[ $? -ne 0 ]]; then
            msg_error "Failed to download template ${OS_TEMPLATE}"
            exit 1
        fi
        msg_ok "Template ${OS_TEMPLATE} downloaded"
    else
        msg_ok "Template ${OS_TEMPLATE} is available"
    fi
}

# LXC-Container erstellen
function create_container() {
    msg_info "Creating LXC container for ${APP} with IP ${HOST_IP}"
    pct create ${CONTAINER_ID} ${TEMPLATE_STORAGE}/${OS_TEMPLATE} \
        --hostname ${CONTAINER_NAME} \
        --storage local-lvm \
        --rootfs ${DISK_SIZE} \
        --memory ${RAM} \
        --cores ${CPU_CORES} \
        --net0 name=eth0,bridge=vmbr0,ip=${HOST_IP}/24,gw=192.168.178.1 \
        --features nesting=1,keyctl=1 \
        --unprivileged 1
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to create LXC container"
        exit 1
    fi
    msg_ok "LXC container created"
}

# LXC starten und Docker installieren
function setup_docker() {
    msg_info "Starting the container"
    pct start ${CONTAINER_ID}
    sleep 5

    msg_info "Installing Docker inside the container"
    pct exec ${CONTAINER_ID} -- bash -c "apt update && apt install -y docker.io docker-compose"
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to install Docker"
        exit 1
    fi
    msg_ok "Docker installed"
}

# Docker-Compose-Setup kopieren und starten
function setup_teddycloud() {
    msg_info "Setting up Docker-Compose for TeddyCloud"
    pct exec ${CONTAINER_ID} -- bash -c "mkdir -p /opt/${CONTAINER_NAME}"
    cat <<EOF | pct exec ${CONTAINER_ID} -- bash -c "cat > /opt/${CONTAINER_NAME}/docker-compose.yml"
version: '3'
services:
  ${CONTAINER_NAME}:
    container_name: ${CONTAINER_NAME}
    hostname: ${CONTAINER_NAME}
    image: ${DOCKER_IMAGE}
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

    pct exec ${CONTAINER_ID} -- bash -c "cd /opt/${CONTAINER_NAME} && docker-compose up -d"
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to start TeddyCloud service"
        exit 1
    fi
    msg_ok "TeddyCloud is now running"
}

# Hauptskript
function main() {
    check_requirements
    check_template
    create_container
    setup_docker
    setup_teddycloud

    msg_info "TeddyCloud setup completed"
    msg_ok "Access TeddyCloud at: http://${HOST_IP}"
}

main
