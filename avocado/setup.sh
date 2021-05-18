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

    Is_mounted "$TCDIST_ROOTMNT"

    idir=$(pwd)

    pushd docker
    ./docker.sh build
    ./docker.sh export
    popd

    sudo mkdir -p "${TCDIST_ROOTMNT}/var/lib/avocado/data/avocado-vt/"

    pushd "${TCDIST_ROOTMNT}/var/lib/avocado/data/avocado-vt/"
    tar xf "${idir}/images/avocado-vt-bootstrap.tar.gz"
    popd
    cp host-tools/*.sh "${TCDIST_ROOTMNT}/root/"
    cp host-tools/kvm "${TCDIST_ROOTMNT}/usr/bin/"
    cp cfg/qemu-base.cfg "${TCDIST_ROOTMNT}/var/lib/avocado/data/avocado-vt/backends/qemu/cfg/base.cfg"
    rm -f "${TCDIST_ROOTMNT}/root/rootfs.ext2"
    cp images/CustomLinux.qcow2 "${TCDIST_ROOTMNT}/var/lib/avocado/data/avocado-vt/images/"
    sed -i 's/rootfs.ext2/\/var\/lib\/avocado\/data\/avocado-vt\/images\/CustomLinux.qcow2/' "${TCDIST_ROOTMNT}/root/run-x86-qemu.sh"
    sed -i 's/,format=raw//' "${TCDIST_ROOTMNT}/root/run-x86-qemu.sh"
}

function Domu_update {
    local domuroot
    Is_mounted "$TCDIST_DOMUMNT"

    cp guest-tools/* "${TCDIST_DOMUMNT}/usr/bin/"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "${TCDIST_DOMUMNT}/etc/ssh/sshd_config"

    echo "Generating guest-os image, this may take a while..."

    case "$TCDIST_BUILDOPT" in
    usb|mmc)
        domuroot="${TCDIST_DOMUMNT}-su/"
    ;;
    dhcp|static)
        domuroot="${TCDIST_NFSDOMU}/"
    ;;
    esac

    mkdir -p images

    sudo virt-make-fs --format=qcow2 "$domuroot" images/CustomLinux.qcow2
    sudo virt-copy-in -a images/CustomLinux.qcow2 cfg/interfaces /etc/network/
    echo "Done."
}

function Updatefs {
    local idir

    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        Set_my_ids
        Create_mount_points
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$TCDIST_NFSDOM0" "$TCDIST_ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$TCDIST_NFSDOMU" "$TCDIST_DOMUMNT"

        Domu_update

        Dom0_update

        sudo umount "$TCDIST_ROOTMNT"
        sudo umount "$TCDIST_DOMUMNT"

    ;;
    usb|mmc)
        Set_my_ids
        Create_mount_points
        idir="${PWD}/../buildroot/output/images"
        sudo mount "${idir}/rootfs-withdomu.ext2" "${TCDIST_ROOTMNT}-su"
        sudo mount "${idir}/rootfs.ext2" "${TCDIST_DOMUMNT}-su"
        Bind_mounts

        Domu_update

        Dom0_update

        sudo umount "$TCDIST_DOMUMNT"
        sudo umount "${TCDIST_DOMUMNT}-su"
        sudo umount "$TCDIST_ROOTMNT"
        sudo umount "${TCDIST_ROOTMNT}-su"
    ;;
    esac

}

function Check_script {
    Shellcheck_bashate setup.sh ../helpers.sh ../default_setup_sh_config docker/docker.sh host-tools/* guest-tools/*
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
