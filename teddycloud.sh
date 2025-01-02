#!/usr/bin/env bash

# App default values
APP="TeddyCloud"
var_tags="media"
var_cpu="2"
var_disk="8"
var_ram="1024"
var_os="debian"
var_version="12"
CONTAINER_NAME="teddycloud"
HOST_IP="192.168.178.190"

# Farben für Ausgaben
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # Reset

# Funktionen für Ausgabe
function msg_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

function msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

function msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Container erstellen und starten
function build_teddycloud_container() {
    msg_info "Creating LXC container for ${APP} with IP ${HOST_IP}"
    
    # Container erstellen
    pct create ${CONTAINER_ID} /var/lib/vz/template/cache/${var_os}-${var_version}-standard_amd64.tar.gz \
        -hostname ${CONTAINER_NAME} \
        -rootfs ${var_disk} \
        -memory ${var_ram} \
        -cores ${var_cpu} \
        -net0 name=eth0,bridge=vmbr0,ip=${HOST_IP}/24,gw=192.168.178.1 \
        -features nesting=1,keyctl=1 \
        -tags ${var_tags}

    if [[ $? -ne 0 ]]; then
        msg_error "Failed to create LXC container"
        exit 1
    fi

    # Auslesen der ID des gerade erstellten Containers
    CONTAINER_ID=$(pct list | grep ${CONTAINER_NAME} | awk '{print $1}')

    if [[ -z "${CONTAINER_ID}" ]]; then
        msg_error "Failed to get the container ID"
        exit 1
    fi

    msg_info "Container ID is ${CONTAINER_ID}"

    # Container starten
    pct start ${CONTAINER_ID}
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to start LXC container"
        exit 1
    fi

    # Warte, bis der Container betriebsbereit ist
    sleep 5

    msg_ok "LXC container created and started successfully"
}

# Update-Skript für die Anwendung
function update_script() {
    msg_info "Checking for updates"
    RELEASE="$(curl -s https://api.github.com/repos/toniebox-reverse-engineering/teddycloud/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')"
    VERSION="${RELEASE#tc_v}"
    msg_info "Latest version is v${VERSION}"

    if [[ ! -f "/opt/${APP}_version.txt" || "${VERSION}" != "$(cat /opt/${APP}_version.txt)" ]]; then
        msg_info "Stopping ${APP}"
        systemctl stop teddycloud
        msg_ok "Stopped ${APP}"

        msg_info "Updating ${APP} to v${VERSION}"
        PREVIOUS_VERSION="$(readlink -f /opt/teddycloud)"
        wget -q "https://github.com/toniebox-reverse-engineering/teddycloud/releases/download/${RELEASE}/teddycloud.amd64.release_v${VERSION}.zip"
        unzip -q -d "/opt/teddycloud-${VERSION}" "teddycloud.amd64.release_v${VERSION}.zip"
        ln -fns "/opt/teddycloud-${VERSION}" /opt/teddycloud
        echo "${VERSION}" >"/opt/${APP}_version.txt"
        cp -R "${PREVIOUS_VERSION}/certs" /opt/teddycloud
        cp -R "${PREVIOUS_VERSION}/config" /opt/teddycloud
        cp -R "${PREVIOUS_VERSION}/data" /opt/teddycloud
        msg_ok "Updated ${APP} to v${VERSION}"

        msg_info "Starting ${APP}"
        systemctl start teddycloud
        msg_ok "Started ${APP}"

        msg_info "Cleaning up"
        rm "teddycloud.amd64.release_v${VERSION}.zip"
        rm -rf "${PREVIOUS_VERSION}"
        msg_ok "Cleaned"
    else
        msg_ok "No update required. ${APP} is already at v${VERSION}"
    fi
    exit
}

# Starten der Erstellung und Aktualisierung
msg_info "Starting the process"
build_teddycloud_container
msg_ok "TeddyCloud setup has been successfully initialized!"
msg_info "Access it using the following URL: http://${HOST_IP}"
