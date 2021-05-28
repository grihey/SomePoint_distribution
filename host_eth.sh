#!/bin/bash

# Sets up bridge for admin machine and connects host external ethernet there

. ./helpers.sh
Load_config

SYSCTLSAVE=".sysctl.save.tmp"

function Bridge_up {
    sudo ip link add name "$1" type bridge
    sudo ip link set dev "$1" up
}

function Bridge_dn {
    sudo ip link set dev "$1" down
    sudo ip link del name "$1"
}

case "$1" in
    up)
        # Save current settings
        sudo sysctl net.bridge.bridge-nf-call-arptables net.bridge.bridge-nf-call-ip6tables net.bridge.bridge-nf-call-iptables > "${SYSCTLSAVE}"
        # These were required for bridging to work between admin machine and host external network.
        # Some details about the settings here: https://wiki.libvirt.org/page/Net.bridge.bridge-nf-call_and_sysctl.conf
        sudo sysctl net.bridge.bridge-nf-call-arptables=0 net.bridge.bridge-nf-call-ip6tables=0 net.bridge.bridge-nf-call-iptables=0

        Bridge_up "$TCDIST_ADMINBR"
        sudo ip a flush dev "$TCDIST_ETHDEV"
        sudo ip link set dev "$TCDIST_ETHDEV" master "$TCDIST_ADMINBR"
        sudo dhclient -v "$TCDIST_ADMINBR"
    ;;
    dn)
        sudo ip a flush dev "$TCDIST_ETHDEV"
        sudo dhclient -v "$TCDIST_ETHDEV"
        Bridge_dn "$TCDIST_ADMINBR"

        if [ -f "${SYSCTLSAVE}" ]; then
            sudo sysctl -p "${SYSCTLSAVE}"
            rm -f "${SYSCTLSAVE}"
        fi
    ;;
esac