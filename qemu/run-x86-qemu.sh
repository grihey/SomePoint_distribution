#!/bin/sh

if [ "$1" = "vda" ] ; then
    ROOTFS_FILE="-drive file=rootfs.ext2,if=virtio,format=raw"
    ROOTFS_CMD="root=/dev/vda"
else
    ROOTFS_FILE=""
    ROOTFS_CMD="root=/dev/nfs nfsroot=192.168.1.101:/srv/nfs/x86-root,tcp,vers=3,nolock ip=::::x86-domu:eth0:dhcp"
fi

qemu-system-x86_64 -m 128 -M pc -enable-kvm -kernel Image $ROOTFS_FILE -append "rootwait $ROOTFS_CMD console=tty1 console=ttyS0" -net nic,model=virtio -net user -nographic
