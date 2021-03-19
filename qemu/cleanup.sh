#!/bin/bash

set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

pushd "$SDIR" > /dev/null
trap "popd > /dev/null" EXIT

. ../helpers.sh
Load_config nocheck

case "$1" in
    distclean)
        Remove_ignores sudo
    ;;
    *)
        if [ -d qemu ]; then
            cd qemu
            sudo make clean
            cd ..
        fi
    ;;
esac
