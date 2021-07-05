#!/bin/bash

DISABLED=0

if [ "$DISABLED" -ne 1 ]; then
    MACFILE1=".vm_1.mac_1"
    MACFILE2=".vm_1.mac_2"

    if [ ! -f "$MACFILE1" ]; then
        printf "%s not found, generated a random qemu/kvm mac address: " "$MACFILE1"
        printf "52:54:00:%02X:%02X:%02X\n" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) | tee "${MACFILE1}"
    fi
    MACADD1=$(< "${MACFILE1}")

    if [ ! -f "$MACFILE2" ]; then
        printf "%s not found, generated a random qemu/kvm mac address: " "$MACFILE2"
        printf "52:54:00:%02X:%02X:%02X\n" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) | tee "${MACFILE2}"
    fi
    MACADD2=$(< "${MACFILE2}")

    QEMUOPT=(-m 256 -M pc -cpu host -enable-kvm)
    QEMUOPT+=(-kernel br_conn.bzImage)
    QEMUOPT+=(-drive file=br_conn.ext2,if=virtio,format=raw)
    QEMUOPT+=(-append "rootwait root=/dev/vda console=ttyS0")
    QEMUOPT+=(-device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=4,disable-legacy=on)
    QEMUOPT+=(-nic tap,model=virtio-net-pci,ifname=tap0,mac=${MACADD1},script=no)
    QEMUOPT+=(-nic tap,model=virtio-net-pci,ifname=tap1,mac=${MACADD2},script=no)
    #QEMUOPT+=(-serial stdio)
    #QEMUOPT+=(-device qemu-xhci -device usb-kbd)
    QEMUOPT+=(-nographic)

    case "$1" in
        netup)
            Interface_up tap0 "$CONBR"
            Interface_up tap1 "$VMBR"
        ;;
        netdn)
            Interface_dn tap1
            Interface_dn tap0
        ;;
        start)
            "$QEMUEXE" "${QEMUOPT[@]}"
        ;;
    esac
fi
