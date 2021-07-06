#!/bin/bash

DISABLED=0

if [ "$DISABLED" -ne 1 ]; then
    PIDFILE=".vm_2.pid"
    MACFILE=".vm_2.mac"

    if [ ! -f "$MACFILE" ]; then
        printf "%s not found, generated a random qemu/kvm mac address: " "$MACFILE"
        printf "52:54:00:%02X:%02X:%02X\n" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) | tee "${MACFILE}"
    fi

    MACADD=$(< "${MACFILE}")
    QEMUOPT=(-m 256 -M pc -cpu host -enable-kvm)
    QEMUOPT+=(-kernel br_secure.bzImage)
    QEMUOPT+=(-drive file=br_secure.ext2,if=virtio,format=raw)
    QEMUOPT+=(-append "rootwait root=/dev/vda console=ttyS0")
    QEMUOPT+=(-device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=5,disable-legacy=on)
    QEMUOPT+=(-nic tap,model=virtio-net-pci,ifname=tap2,mac=${MACADD},script=no)
    #QEMUOPT+=(-serial stdin)
    #QEMUOPT+=(-device qemu-xhci -device usb-kbd)
    QEMUOPT+=(-nographic)

    case "$1" in
        netup)
            Interface_up tap2 "$CONBR"
        ;;
        netdn)
            Interface_dn tap2
        ;;
        start)
            "$QEMUEXE" "${QEMUOPT[@]}" &
            sleep 0.1s
            echo "$!" > "$PIDFILE"
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
