#!/bin/bash

TCDIST_VM_NAME="br_conn"

function Interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface eth1 inet manual"
    echo ""
    echo "iface default inet dhcp"
}

TCDIST_VM_INPUTS="vm_1.sh"
TCDIST_VM_OUTPUTS="${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.ext2 ${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.${TCDIST_KERNEL_IMAGE_FILE}"

