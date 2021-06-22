#!/bin/bash

# Include generic rootfs adjustments (Will load vm specific options too)
. ../adjust_rootfs.sh -hostname -interfaces -ssh "$@"

if [ "${TCDIST_ARCH}_${TCDIST_PLATFORM}" == "arm64_ls1012afrwy" ]; then
    echo "Mount debug fs"
    set -x
    e2cp "${2}:/etc/fstab" fstab.tmp
    Mount_debug_fs >> fstab.tmp
    e2cp -P 644 -O 0 -G 0 fstab.tmp "${2}:/etc/fstab"
    cat fstab.tmp
    rm -f fstab.tmp
    set +x
fi
