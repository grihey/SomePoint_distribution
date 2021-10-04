#!/bin/bash
# shellcheck disable=SC2034 # disable unused variable warnings

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "auto eth1"
    echo "iface eth1 inet static"
    echo "    address ${TCDIST_INTERNAL_NET}.1"
    echo "    netmask 255.255.255.0"
    echo ""
    echo "# SSH interface"
    echo "auto eth2"
    echo "iface eth2 inet dhcp"
    echo "    up ifmetric eth2 100"
    echo ""
    echo "iface default inet dhcp"
}

ARFS_OPTIONS="-interfaces -ssh -inittab s"
