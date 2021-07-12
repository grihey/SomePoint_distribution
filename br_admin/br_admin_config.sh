#!/bin/bash
# shellcheck disable=SC2034 # disable unused variable warnings
# Configuration for buildroot admin

TCDIST_VM_NAME="br_admin"

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface default inet dhcp"
}

ARFS_OPTIONS="-hostname -interfaces -ssh -inittab sv"
