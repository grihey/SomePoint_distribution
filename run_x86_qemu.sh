#!/bin/bash
# Adapted from buildroot start-qemu.sh script

. helpers.sh
Load_config

if [ "$PLATFORM" != "x86" ] || [ "$HYPERVISOR" != "kvm" ] ; then
    echo "Bad platform, only supported for x86 / kvm." >&2
    exit
fi

IMAGE_DIR="buildroot/output/images"

if [ "${1}" = "serial-only" ]; then
    EXTRA_ARGS='-nographic'
else
    EXTRA_ARGS='-serial stdio'
fi

case "$BUILDOPT" in
dhcp|static)
    # Network build uses NFS rootfs
    FILE_ARG=""
    ROOTFS_ARG="root=/dev/nfs nfsroot=${NFSSERVER}:${NFSDOM0},tcp,vers=3 ip=::::x86-dom0:eth0:dhcp nfsrootdebug"
;;
*)
    # SD or USB boot, use static image
    FILE_ARG="-drive file=${IMAGE_DIR}/rootfs-withdomu.ext2,if=virtio,format=raw"
    ROOTFS_ARG="root=/dev/vda"
;;
esac

# Argument variables contain options separated with spaces and are purposefully unquoted
exec sudo qemu-system-x86_64 -m 512 -M pc -cpu host -enable-kvm -kernel "${IMAGE_DIR}/bzImage" ${FILE_ARG} \
    -append "rootwait ${ROOTFS_ARG} console=tty1 console=ttyS0" \
    -net nic,model=virtio -net user,hostfwd=tcp::222-:22,hostfwd=tcp::2222-:222 ${EXTRA_ARGS}
