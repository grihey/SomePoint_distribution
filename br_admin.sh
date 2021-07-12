#!/bin/bash

# This script starts or stops admin machine on qemu
# Select serial connection from qemu window to access
# It is assumed that adminbr0 bridge is set up earlier with e.g. host_eth.sh

. ./helpers.sh
Load_config

function Interface_up {
    sudo ip tuntap add "$1" mode tap
    sudo ip link set "$1" up
    sudo ip link set dev "$1" master "$2"
}

function Interface_dn {
    sudo ip link set "$1" down
    sudo ip tuntap del "$1" mode tap
}

MACFILE="${TCDIST_OUTPUT}/.tcdist.macs"

if [ ! -f "${MACFILE}" ]; then
    echo "Generating macs to ${MACFILE}" >&2
    ./genmacs.sh > "${MACFILE}"
fi

# Get first mac from file
MACADD=$(sed "1q;d" "$MACFILE")
TAPIF="tap0"
PIDFILE="${TCDIST_OUTPUT}/.br_admin.pid.tmp"
QEMUEXE="qemu-system-x86_64"

QEMUOPT=(-m 4096 -M pc -cpu host -enable-kvm)
QEMUOPT+=(-kernel "${TCDIST_OUTPUT}/${TCDIST_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.bzImage")
QEMUOPT+=(-drive "file=${TCDIST_OUTPUT}/${TCDIST_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.ext2,if=virtio,format=raw")
QEMUOPT+=(-append "rootwait root=/dev/vda console=ttyS0")
QEMUOPT+=(-device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=3,disable-legacy=on)
QEMUOPT+=(-nic tap,model=virtio-net-pci,ifname=${TAPIF},mac=${MACADD},script=no)
#QEMUOPT+=(-serial stdin)
#QEMUOPT+=(-device qemu-xhci -device usb-kbd)
#QEMUOPT+=(-nographic)

case "$1" in
    up)
        Interface_up "${TAPIF}" "${TCDIST_ADMIN_BRIDGE}"
    ;;
    dn)
        Interface_dn "${TAPIF}"
    ;;
    start)
        set +e
        Interface_up "${TAPIF}" "${TCDIST_ADMIN_BRIDGE}"

        sudo "$QEMUEXE" "${QEMUOPT[@]}" &
        sleep 0.1s
        CPID="$(ps --ppid $! -o pid=)"
        echo "$CPID" > "$PIDFILE"
    ;;
    stop)
        if [ ! -f "$PIDFILE" ]; then
            echo "$PIDFILE not found" >&2
            exit 1
        fi

        CPID=$(< "$PIDFILE")

        if sudo kill "$CPID"; then
            rm -f "$PIDFILE"
            Interface_dn "${TAPIF}"
        else
            echo "Stop failed" >&2
        fi
    ;;
    kill)
        set +e
        # Yes, this is slightly dangerous, use only as last resort if stop does not work
        sudo killall "$QEMUEXE"
        rm -f "$PIDFILE"
        Interface_dn "${TAPIF}"
    ;;
    *)
        echo "Usage: $0 <start|stop>"
        echo ""
        exit 1
    ;;
esac
