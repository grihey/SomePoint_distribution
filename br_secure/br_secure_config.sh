#!/bin/bash
# Configuration for buildroot secure-os

TCDIST_VM_NAME="br_secure"

function Interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface default inet dhcp"
}

TCDIST_VM_OUTPUTS="${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.ext2 ${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.${TCDIST_KERNEL_IMAGE_FILE} vm_2.sh"
TCDIST_VM_DEPS="${TCDIST_VM_OUTPUTS}"
