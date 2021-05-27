#!/bin/bash

DISABLED=0

if [ "$DISABLED" -ne 1 ]; then
    PIDFILE=".vm_1.pid"

    QEMUOPT=(-m 256 -M pc -cpu host -enable-kvm)
    QEMUOPT+=(-kernel br_conn.bzImage)
    QEMUOPT+=(-drive file=br_conn.ext2,if=virtio,format=raw)
    QEMUOPT+=(-append "rootwait root=/dev/vda console=ttyS0")
    QEMUOPT+=(-device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=4,disable-legacy=on)
    QEMUOPT+=(-nic tap,model=virtio-net-pci,ifname=tap1,mac=CE:11:CA:11:00:01,script=no)
    #QEMUOPT+=(-serial stdin)
    #QEMUOPT+=(-device qemu-xhci -device usb-kbd)
    QEMUOPT+=(-nographic)

    case "$1" in
        netup)
            Interface_up tap1 "$CONBR"
        ;;
        netdn)
            Interface_dn tap1
        ;;
        start)
            "$QEMUEXE" "${QEMUOPT[@]}"
            #echo "$!" > "$PIDFILE"
        ;;
        stop)
            CPID=$(< "$PIDFILE")
            if [ -n "$CPID" ]; then
                kill "$CPID"
                rm -f "$PIDFILE"
            else
                echo "$PIDFILE" not found >&2
            fi
        ;;
    esac
fi
