#!/bin/bash
# Adapted from buildroot start-qemu.sh script

. helpers.sh
Load_config

if [ "$TCDIST_PLATFORM" != "x86" ] || [ "$TCDIST_HYPERVISOR" != "kvm" ] ; then
    echo "Bad platform, only supported for x86 / kvm." >&2
    exit
fi

IMAGE="buildroot/output/images/rootfs-withdomu.ext2"
BZIMAGE="buildroot/output/images/bzImage"

SERIAL_ONLY=0
# Dom0 port
PORT1=2222
# DomU port
PORT2=22222

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
    -ss|-snapshot)
        EXTRA_ARGS="${EXTRA_ARGS} -snapshot"
        shift # past value
    ;;
    -p1|-port1)
        PORT1="$2"
        shift # past argument
        shift # past value
    ;;
    -p2|-port2)
        PORT2="$2"
        shift # past argument
        shift # past value
    ;;
    -i|-image)
        IMAGE="$2"
        shift # past argument
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

case "$TCDIST_BUILDOPT" in
dhcp|static)
    # Network build uses NFS rootfs. However, secure-os contains docker
    # installation which does not work too well with NFS. For that purpose,
    # lets provide a custom .ext2 filesystem image also.
    if [ "$TCDIST_SECUREOS" = "1" ] ; then
        FILE_ARG="-drive file=${TCDIST_GKBUILD}/docker.ext2,if=virtio,format=raw"
    else
        FILE_ARG=""
    fi
    ROOTFS_ARG="root=/dev/nfs nfsroot=${TCDIST_NFSSERVER}:${TCDIST_NFSDOM0},tcp,vers=3 ip=::::x86-dom0:eth0:dhcp nfsrootdebug"
;;
*)
    # SD or USB boot, use static image
    FILE_ARG="-drive file=${IMAGE},if=virtio,format=raw"
    ROOTFS_ARG="root=/dev/vda"
;;
esac

ENABLE_KVM="-cpu qemu64"
if groups | grep kvm; then
    ENABLE_KVM="-cpu host -enable-kvm"
    echo "KVM enabled"
else
    echo "KVM disabled"
fi

# Argument variables contain options separated with spaces and are purposefully unquoted
exec qemu-system-x86_64 -m 1024 -M pc ${ENABLE_KVM} -kernel "${BZIMAGE}" ${FILE_ARG} \
    -append "rootwait ${ROOTFS_ARG} console=tty1 console=ttyS0" \
    -net nic,model=virtio -net user,hostfwd=tcp::$PORT1-:22,hostfwd=tcp::$PORT2-:222 ${EXTRA_ARGS}
