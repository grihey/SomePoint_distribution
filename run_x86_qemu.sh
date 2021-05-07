#!/bin/bash
# Adapted from buildroot start-qemu.sh script

. helpers.sh
Load_config

if [ "$PLATFORM" != "x86" ] || [ "$HYPERVISOR" != "kvm" ] ; then
    echo "Bad platform, only supported for x86 / kvm." >&2
    exit
fi

IMAGE_DIR="buildroot/output/images"

SERIAL_ONLY=0

while [ "$#" -gt 0 ]; do
    case "$1" in
    -s|serial-only)
        SERIAL_ONLY=1
        shift # past value
    ;;
    -r|no-reboot)
        EXTRA_ARGS="${EXTRA_ARGS} -no-reboot"
        shift # past value
    ;;
    *)    # device name and invalid argument
        # Argument that starts with "-" have been prosessed already.
        if [[ $1 == * ]]; then
            echo "Argument <$1> not supported. You might have missed a space before size value!"
            exit 1
        fi
        shift # past argument
    ;;
    esac
done

if [ "${SERIAL_ONLY}" = "1" ]; then
    EXTRA_ARGS="${EXTRA_ARGS} -nographic"
else
    EXTRA_ARGS="${EXTRA_ARGS} -serial stdio"
fi

case "$BUILDOPT" in
dhcp|static)
    # Network build uses NFS rootfs. However, secure-os contains docker
    # installation which does not work too well with NFS. For that purpose,
    # lets provide a custom .ext2 filesystem image also.
    if [ "$SECURE_OS" = "1" ] ; then
        FILE_ARG="-drive file=${GKBUILD}/docker.ext2,if=virtio,format=raw"
    else
        FILE_ARG=""
    fi
    ROOTFS_ARG="root=/dev/nfs nfsroot=${NFSSERVER}:${NFSDOM0},tcp,vers=3 ip=::::x86-dom0:eth0:dhcp nfsrootdebug"
;;
*)
    # SD or USB boot, use static image
    FILE_ARG="-drive file=${IMAGE_DIR}/rootfs-withdomu.ext2,if=virtio,format=raw"
    ROOTFS_ARG="root=/dev/vda"
;;
esac

# Argument variables contain options separated with spaces and are purposefully unquoted
exec sudo qemu-system-x86_64 -m 1024 -M pc -cpu host -enable-kvm -kernel "${IMAGE_DIR}/bzImage" ${FILE_ARG} \
    -append "rootwait ${ROOTFS_ARG} console=tty1 console=ttyS0" \
    -net nic,model=virtio -net user,hostfwd=tcp::222-:22,hostfwd=tcp::2222-:222 ${EXTRA_ARGS}
