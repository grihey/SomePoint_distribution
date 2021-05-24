#!/bin/bash
# Configuration for buildroot admin

TCDIST_VM_NAME="br_admin"

function Interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface default inet dhcp"
}

TCDIST_VM_OUTPUTS="${TCDIST_VM_NAME}.ext2 ${TCDIST_VM_NAME}.bzImage"
TCDIST_VM_DEPS="${TCDIST_VM_OUTPUTS}"

# Where to put the rootfs and kernel images and additional files of the vms
TCDIST_ADMIN_DIR=/root
TCDIST_ADMIN_MODE=755
TCDIST_ADMIN_UID=0
TCDIST_ADMIN_GID=0
