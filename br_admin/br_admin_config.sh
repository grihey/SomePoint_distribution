#!/bin/bash
# shellcheck disable=SC2034 # disable unused variable warnings
# Configuration for buildroot admin

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface default inet dhcp"
    echo ""
    echo "source-directory /etc/network/interfaces.d"
    echo ""
}

ARFS_OPTIONS="-interfaces -ssh -inittab sv"
