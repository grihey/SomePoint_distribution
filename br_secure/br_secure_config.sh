#!/bin/bash
# shellcheck disable=SC2034 # disable unused variable warnings
# Configuration for buildroot secure-os

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet static"
    echo "    address ${TCDIST_INTERNAL_NET}.2"
    echo "    netmask 255.255.255.0"
    echo "    gateway ${TCDIST_INTERNAL_NET}.1"
    echo ""
    echo "iface default inet dhcp"
}

ARFS_OPTIONS="-hostname -interfaces -ssh"
case "${TCDIST_ARCH}_${TCDIST_PLATFORM}" in
    x86_qemu)
        ARFS_OPTIONS+=" -inittab s -netrcadd"
    ;;
esac
