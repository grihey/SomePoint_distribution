#!/bin/bash

. ../helpers.sh

Load_config ""

function Config {
    cat cfg/buildroot_config >> ../buildroot/.config
    cd ../docker || exit
    docker run --privileged -it --rm --entrypoint "" -v "${PWD}/..:/usr/src" -w /usr/src/buildroot rpi4_kernel_build_env make BR2_EXTERNAL=/usr/src/avocado/br2-external olddefconfig
}

function Dom0_update {
    local idir

    Is_mounted "$ROOTMNT"

    idir=$(pwd)

    pushd docker
    ./docker.sh build
    ./docker.sh export
    popd

    sudo mkdir -p "${ROOTMNT}/var/lib/avocado/data/avocado-vt/"

    pushd "${ROOTMNT}/var/lib/avocado/data/avocado-vt/"
    tar xf "${idir}/images/avocado-vt-bootstrap.tar.gz"
    popd
    cp host-tools/*.sh "${ROOTMNT}/root/"
    cp host-tools/kvm "${ROOTMNT}/usr/bin/"
    cp cfg/qemu-base.cfg "${ROOTMNT}/var/lib/avocado/data/avocado-vt/backends/qemu/cfg/base.cfg"
    rm "${ROOTMNT}/root/rootfs.ext2"
    cp images/CustomLinux.qcow2 "${ROOTMNT}/var/lib/avocado/data/avocado-vt/images/"
    sed -i 's/rootfs.ext2/\/var\/lib\/avocado\/data\/avocado-vt\/images\/CustomLinux.qcow2/' "${ROOTMNT}/root/run-x86-qemu.sh"
    sed -i 's/,format=raw//' "${ROOTMNT}/root/run-x86-qemu.sh"
}

function Domu_update {
    local domuroot
    Is_mounted "$DOMUMNT"

    cp guest-tools/* "${DOMUMNT}/usr/bin/"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "${DOMUMNT}/etc/ssh/sshd_config"

    echo "Generating guest-os image, this may take a while..."

    case "$BUILDOPT" in
    usb|mmc)
        domuroot="${DOMUMNT}-su/"
    ;;
    dhcp|static)
        domuroot="${NFSDOMU}/"
    ;;
    esac

    sudo virt-make-fs --format=qcow2 "$domuroot" images/CustomLinux.qcow2
    sudo virt-copy-in -a images/CustomLinux.qcow2 cfg/interfaces /etc/network/
    echo "Done."
}

function Updatefs {
    local idir

    case "$BUILDOPT" in
    dhcp|static)
        Set_my_ids
        Create_mount_points
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOM0" "$ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOMU" "$DOMUMNT"

        Domu_update

        Dom0_update

        sudo umount "$ROOTMNT"
        sudo umount "$DOMUMNT"

    ;;
    usb|mmc)
        Set_my_ids
        Create_mount_points
        idir="${PWD}/../buildroot/output/images"
        sudo mount "${idir}/rootfs-withdomu.ext2" "${ROOTMNT}-su"
        sudo mount "${idir}/rootfs.ext2" "${DOMUMNT}-su"
        Bind_mounts

        Domu_update

        Dom0_update

        sudo umount "$DOMUMNT"
        sudo umount "${DOMUMNT}-su"
        sudo umount "$ROOTMNT"
        sudo umount "${ROOTMNT}-su"
    ;;
    esac

}

function Check_script {
    shellcheck -x setup.sh docker/docker.sh host-tools/* guest-tools/*
    # Ignore "E0006 Line too long" errors
    bashate -i E006 setup.sh docker/docker.sh host-tools/* guest-tools/*
}

function Show_help {
    echo "Usage $0 <command>"
    echo ""
    echo "Commands:"
    echo "    help                              Show this help"
    echo "    updatefs                          Copy avocado related files to rootfs"
    echo "    config                            Configure buildroot for avocado support"
    echo "    check_script                      Check any avocado scripts with"
    echo "                                      shellcheck and bashate"
    exit 0
}

CMD="${1,,}"
CMD="${CMD^}"

case "$CMD" in
    ""|Help|-h|--help)
        Show_help >&2
    ;;
esac

Fn_exists "$CMD"
"$CMD" "$@"
