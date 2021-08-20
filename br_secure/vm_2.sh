#!/bin/bash

DISABLED=0

if [ "$DISABLED" -ne 1 ]; then
    MACFILE="br_secure.mac"

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
    QEMUOPT+=(-netdev user,id=virtio-net-pci0,hostfwd=tcp::2302-:22) # SSH network interface
    QEMUOPT+=(-device virtio-net-pci,netdev=virtio-net-pci0)
    #QEMUOPT+=(-serial stdin)
    #QEMUOPT+=(-device qemu-xhci -device usb-kbd)
    QEMUOPT+=(-nographic)

    case "$1" in
        netup)
            Interface_up tap2 "$VMBR"
        ;;
        netdn)
            Interface_dn tap2
        ;;
        start)
            "$QEMUEXE" "${QEMUOPT[@]}"
        ;;
    esac
fi
