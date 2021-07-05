#!/bin/bash

# This script handles network settings and starting and stopping vms inside admin machine

# Export env variables and functions so they can be used in vm_*.sh
set -a

function Bridge_up {
    ip link add name "$1" type bridge
    ip link set dev "$1" up
}

function Bridge_dn {
    ip link set dev "$1" down
    ip link del name "$1"
}

function Interface_up {
    ip tuntap add "$1" mode tap
    ip link set "$1" up
    if [ -n "$2" ]; then
        ip link set dev "$1" master "$2"
    fi
}

function Interface_dn {
    ip link set "$1" down
    ip tuntap del "$1" mode tap
}

ETHDEV="eth0"
VMBR="vmbr0"
CONBR="conbr0"
QEMUEXE="qemu-system-x86_64"
SYSCTLSAVE=".sysctl.save"
SCRSESSION="tcs"

case "$1" in
    netup)
        #sysctl net.bridge.bridge-nf-call-arptables net.bridge.bridge-nf-call-ip6tables net.bridge.bridge-nf-call-iptables > "$SYSCTLSAVE"
        #sysctl net.bridge.bridge-nf-call-arptables=0 net.bridge.bridge-nf-call-ip6tables=0 net.bridge.bridge-nf-call-iptables=0
        Bridge_up "$CONBR"
        Bridge_up "$VMBR"

        ip a flush dev "$ETHDEV"
        ip link set dev "$ETHDEV" master "$CONBR"
        killall udhcpc > /dev/null 2>&1
        udhcpc -i "$CONBR" > /dev/null 2>&1 &

        for S in vm_*.sh; do
            "./$S" netup
        done
    ;;
    netdn)
        for S in vm_*.sh; do
            "./$S" netdn
        done

        ip a flush dev "$ETHDEV"
        killall udhcpc
        udhcpc -i "$ETHDEV"

        Bridge_dn "$VMBR"
        Bridge_dn "$CONBR"

        if [ -f "$SYSCTLSAVE" ]; then
            sysctl -p "$SYSCTLSAVE"
            rm -f "$SYSCTLSAVE"
        fi
    ;;
    start)
        ARG="-d -m"
        for S in vm_*.sh; do
            screen -S "$SCRSESSION" $ARG "./$S" start
            sleep 0.5
            ARG="-X screen"
        done
    ;;
    stop)
        screen -S "$SCRSESSION" -X quit
    ;;
    kill)
        # Use as a last resort
        killall "$QEMUEXE"
    ;;
esac
