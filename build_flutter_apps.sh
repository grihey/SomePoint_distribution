#!/bin/bash

#
# Builds Flutter apps and places them to mounted filesystems
#
# This script will take some time
#

set -eo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function desktop_file_text {
    local APP_NAME=$1
    local APP_PATH=$2

    cat << EOT
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=${APP_NAME}
Exec=${APP_PATH}/gtk-make-and-run.sh
Terminal=true
Type=Application
EOT
}

function create_desktop_file {
    # Creates desktop file for given app to user skeleton
    local APP_NAME=$1
    local FLAVOR=$2 # debug|release
    local DOMAIN_ROOT=$3

    local FILE_PATH=${DOMAIN_ROOT}/etc/skel/Desktop/${APP_NAME}-${FLAVOR}.desktop

    mkdir -p ${DOMAIN_ROOT}/etc/skel/Desktop
    desktop_file_text "${APP_NAME} (${FLAVOR})" /opt/flutter/${APP_NAME}-arm64-gtk-${FLAVOR} \
        > ${FILE_PATH}
    chmod +x ${FILE_PATH}
}

function build_to {
    # Builds app to given target folder. If target exists, it's overridden.
    local MAKE_RULE=$1
    local TARGET=$2

    ./shim.sh make ${MAKE_RULE}
    [ -e ${TARGET} ] && rm -rf ${TARGET}
    mv out/${MAKE_RULE} ${TARGET}
    # Write access is needed before we get the Flutter shell cross-compilation done
    chmod a+w ${TARGET}
}

function deploy_app {
    # Builds and deploys app to domain FS
    local DOMAIN=$1 # rootfs|domufs
    local APP_NAME=$2
    local SRC_PATH=$3

    local DOMAIN_ROOT=${DIR}/mnt/${DOMAIN}

    mkdir -p app
    cp -r ${SRC_PATH}/* app
    mkdir -p ${DOMAIN_ROOT}/opt/flutter
    build_to app-arm64-gtk-debug ${DOMAIN_ROOT}/opt/flutter/${APP_NAME}-arm64-gtk-debug
    build_to app-arm64-gtk-release ${DOMAIN_ROOT}/opt/flutter/${APP_NAME}-arm64-gtk-release

    create_desktop_file ${APP_NAME} debug ${DOMAIN_ROOT}
    create_desktop_file ${APP_NAME} release ${DOMAIN_ROOT}

    rm -rf app
}

if [ -f /.dockerenv ]; then
    echo "This is not supposed to be ran in Docker" >&2
    exit 2
fi

if [ ! -e ${DIR}/mnt/rootfs ]; then
    echo "Mount rootfs first: ./setup.sh mount <device>" >&2
    exit 1
fi

# Use either docker/flutter-shim or ../docker/flutter-shim - latter is just a guess
pushd docker/flutter-shim >/dev/null 2>&1 || pushd ../docker/flutter-shim >/dev/null

echo "Using flutter-shim from $(pwd)"

[ ! -e samples ] && git clone https://github.com/flutter/samples.git

deploy_app rootfs timeflow samples/web/timeflow
deploy_app rootfs form_app samples/form_app

popd >/dev/null
