#!/bin/bash

export TCDIST_VM_NAME="br_secure"

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Include generic rootfs adjustment functions
# Disable shellcheck warning about variable source name
# shellcheck disable=SC1090
. "${SDIR}/../adjust_rootfs.sh" "$1"

Arfs_load_config
# Variable purposefully unquoted, it contains list of space separated options
# shellcheck disable=SC2086
Arfs_apply ${ARFS_OPTIONS} "$@"

if [ "${TCDIST_ARCH}_${TCDIST_PLATFORM}" == "arm64_ls1012afrwy" ]; then
    echo "Mount debug fs"
    set -x
    e2cp "${2}:/etc/fstab" "${TCDIST_TMPDIR}"/fstab.tmp
    echo "debugfs    /sys/kernel/debug      debugfs  defaults  0 0" >> "${TCDIST_TMPDIR}"/fstab.tmp
    e2cp -P 644 -O 0 -G 0 "${TCDIST_TMPDIR}"/fstab.tmp "${2}:/etc/fstab"
    cat "${TCDIST_TMPDIR}"/fstab.tmp
    rm -f "${TCDIST_TMPDIR}"/fstab.tmp
    set +x
fi
