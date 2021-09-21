#!/bin/bash

TCDIST_VM_NAME="br_secure"

# Include generic rootfs adjustment functions
. ${TCDIST_DIR}/adjust_rootfs.sh "$1"

Arfs_load_config
# Variable purposefully unquoted, it contains list of space separated options
# shellcheck disable=SC2086
Arfs_apply ${ARFS_OPTIONS} "$@"

if [ "${TCDIST_ARCH}_${TCDIST_PLATFORM}" == "arm64_ls1012afrwy" ]; then
    echo "Mount debug fs"
    set -x
    e2cp "${2}:/etc/fstab" fstab.tmp
    echo "debugfs    /sys/kernel/debug      debugfs  defaults  0 0" >> fstab.tmp
    e2cp -P 644 -O 0 -G 0 fstab.tmp "${2}:/etc/fstab"
    cat fstab.tmp
    rm -f fstab.tmp
    set +x
fi
