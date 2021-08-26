#!/bin/bash

QEMU_SYSTEM_CPU=6
QEMU_SYSTEM_MEMORY=8G

function Help {
    echo "Usage:"
    echo "$0 <image> <qcow2_file_system>"
}

if ! [ -f "$1" ];
then
    echo "iso image missing"
    Help
    exit 1
fi

if ! [ -f "$2" ];
then
    echo "Missing qcow2 file system image"
    Help
    exit 1
fi

qemu-system-x86_64 \
    -cpu host \
    -smp $QEMU_SYSTEM_CPU \
    -m $QEMU_SYSTEM_MEMORY \
    -cdrom $1 \
    -display sdl \
    -drive file=$2,format=qcow2 \
    -enable-kvm \
    -no-reboot
