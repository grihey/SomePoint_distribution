#!/bin/bash

# This script starts or stops admin machine on qemu
# Select serial connection from qemu window to access
# It is assumed that adminbr0 bridge is set up earlier with e.g. host_eth.sh

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Disable warning about shellcheck not able to follow variable path
# shellcheck disable=SC1090
. "${SDIR}/helpers.sh"
Load_config

PIDFILE="${TCDIST_OUTPUT}/.br_admin.pid.tmp"
QEMUEXE="qemu-system-x86_64"

QEMUOPT=(-m 4096 -M pc -cpu host -enable-kvm)
QEMUOPT+=(-kernel "${TCDIST_OUTPUT}/${TCDIST_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.bzImage")
QEMUOPT+=(-drive "file=${TCDIST_OUTPUT}/${TCDIST_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.ext2,if=virtio,format=raw")
QEMUOPT+=(-append "rootwait root=/dev/vda console=ttyS0")
QEMUOPT+=(-netdev "user,id=virtio-net-pci0,hostfwd=tcp::2222-:22")
QEMUOPT+=(-device "virtio-net-pci,netdev=virtio-net-pci0")

case "$1" in
    start)
        set +e

        "$QEMUEXE" "${QEMUOPT[@]}" &
        echo "$!" > "$PIDFILE"
    ;;
    stop)
        if [ ! -f "$PIDFILE" ]; then
            echo "$PIDFILE not found" >&2
            exit 1
        fi

        CPID=$(< "$PIDFILE")

        if kill "$CPID"; then
            rm -f "$PIDFILE"
        else
            echo "Stop failed" >&2
        fi
    ;;
    kill)
        set +e
        # Yes, this is slightly dangerous, use only as last resort if stop does not work
        killall "$QEMUEXE"
        rm -f "$PIDFILE"
    ;;
    console)
        set +e
        # connect standard io to serial console of the qemu guest
        QEMUOPT+=(-nographic)
        # Change qemu control hotkey to CTRL-B as screen uses CTRL-A
        QEMUOPT+=(-echr 2)

        "$QEMUEXE" "${QEMUOPT[@]}"
    ;;
    check_script)
        Shellcheck_bashate "${BASH_SOURCE[0]}" "${SDIR}/helpers.sh"
    ;;
    *)
        echo "Usage: $0 <start|stop|kill|console>"
        echo ""
        echo "  start - start emulation with qemu in window"
        echo "   stop - stop emulation"
        echo "   kill - kill all running qemus (last resort)"
        echo "console - start qemu with serial console in stdio (CTRL-B as qemu hotkey)"
        echo ""
        exit 1
    ;;
esac
