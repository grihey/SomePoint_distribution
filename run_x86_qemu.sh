#!/bin/bash
# Adapted from buildroot start-qemu.sh script

. default_setup_sh_config
. .setup_sh_config

if [ "$PLATFORM" != "x86" ] || [ "$HYPERVISOR" != "KVM" ] ; then
    echo "Bad platform, only supported for x86 / KVM." >&2
    exit
fi

IMAGE_DIR="buildroot/output/images"

if [ "${1}" = "serial-only" ]; then
    EXTRA_ARGS='-nographic'
else
    EXTRA_ARGS='-serial stdio'
fi

case "$BUILDOPT" in
0|1|MMC|USB)
    # SD or USB boot, use static image
    FILE_ARG="-drive file=${IMAGE_DIR}/rootfs.ext2,if=virtio,format=raw"
    ROOTFS_ARG="root=/dev/vda"
    ;;
*)
    # Any other uses NFS rootfs
    FILE_ARG=""
    ROOTFS_ARG="root=/dev/nfs nfsroot=${NFSSERVER}:${NFSDOM0},tcp,vers=3 ip=::::x86-dom0:eth0:dhcp nfsrootdebug"
    ;;
esac

exec sudo qemu-system-x86_64 -m 512 -M pc -enable-kvm -kernel ${IMAGE_DIR}/bzImage ${FILE_ARG} -append "rootwait ${ROOTFS_ARG} console=tty1 console=ttyS0"  -net nic,model=virtio -net user,hostfwd=tcp::10022-:22  ${EXTRA_ARGS}
