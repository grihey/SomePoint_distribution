#!/bin/bash

set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

pushd "$SDIR" > /dev/null

. ../helpers.sh

case "$1" in
    distclean)
        remove_ignores sudo
    ;;
    *)
        if [ -d qemu ]; then
            cd qemu
            sudo make clean
            cd ..
        fi
    ;;
esac

popd > /dev/null
