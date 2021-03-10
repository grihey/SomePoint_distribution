#!/bin/bash

#
# Builds Flutter apps and places them to mounted filesystems
#
# This script will take some time
#

set -eo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function Desktop_file_text {
    local app_name="$1"
    local app_path="$2"

    cat << EOT
#!/usr/bin/env xdg-open
[Desktop Entry]
Name=${app_name}
Exec=${app_path}/gtk-make-and-run.sh
Terminal=true
Type=Application
EOT
}

function Create_desktop_file {
    # Creates desktop file for given app to user skeleton
    local app_name="$1"
    local flavor="$2" # debug|release
    local domain_root="$3"

    local file_path="${domain_root}/etc/skel/Desktop/${app_name}-${flavor}.desktop"

    mkdir -p "${domain_root}/etc/skel/Desktop"
    Desktop_file_text "${app_name} (${flavor})" "/opt/flutter/${app_name}-arm64-gtk-${flavor}" \
        > "${file_path}"
    chmod +x "${file_path}"
}

function Build_to {
    # Builds app to given target folder. If target exists, it's overridden.
    local make_rule="$1"
    local target="$2"

    ./shim.sh make "${make_rule}"
    [ -e "${target}" ] && rm -rf "${target}"
    mv "out/${make_rule}" "${target}"
    # Write access is needed before we get the Flutter shell cross-compilation done
    chmod a+w "${target}"
}

function Deploy_app {
    # Builds and deploys app to domain FS
    local domain="$1" # rootfs|domufs
    local app_name="$2"
    local src_path="$3"

    local domain_root="${DIR}/mnt/${domain}"

    mkdir -p app
    cp -r "${src_path}"/* app
    mkdir -p "${domain_root}/opt/flutter"
    Build_to app-arm64-gtk-debug "${domain_root}/opt/flutter/${app_name}-arm64-gtk-debug"
    Build_to app-arm64-gtk-release "${domain_root}/opt/flutter/${app_name}-arm64-gtk-release"

    Create_desktop_file "${app_name}" debug "${domain_root}"
    Create_desktop_file "${app_name}" release "${domain_root}"

    rm -rf app
}

if [ -f /.dockerenv ]; then
    echo "This is not supposed to be ran in Docker" >&2
    exit 2
fi

if ! mountpoint -q -- "${DIR}/mnt/rootfs"; then
    echo "Mount rootfs first: ./setup.sh mount <device>" >&2
    exit 1
fi

pushd flutter-shim >/dev/null

[ ! -e samples ] && git clone https://github.com/flutter/samples.git

Deploy_app rootfs timeflow samples/web/timeflow
Deploy_app rootfs form_app samples/form_app

popd >/dev/null
