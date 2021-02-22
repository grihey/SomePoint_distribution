#!/bin/bash

function on_exit_cleanup {
    set +e
    if [ -n "$TMPDIR" ]; then
        rm -rf "$TMPDIR"
    fi
    popd > /dev/null
}

set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Change to the script directory and set cleanup on exit
pushd "$SDIR" > /dev/null
trap on_exit_cleanup EXIT

. helpers.sh
. text_generators.sh

# Stuff that needs to be done before loading config files
case "$1" in
    defconfig)
        defconfig
        exit 0
    ;;
    kvmconfig)
        kvmconfig
        exit 0
    ;;
    x86config)
        x86config
        exit 0
    ;;
    *)
        if [ ! -f .setup_sh_config ]; then
            echo ".setup_sh_config not found" >&2
            defconfig
        fi
    ;;
esac

# Load defaults in case .setup_sh_config is missing any settings
# for example .setup_sh_config could be from older revision
. default_setup_sh_config
. .setup_sh_config
set_ipconfraspi

CCACHE=

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    CCACHE_DIR="$(pwd)/.ccache"
    CCACHE_MAXSIZE=10G
    export CCACHE_DIR
    export CCACHE_MAXSIZE
fi

function generate_disk_image {
    local IDIR
    local BDIR
    local RDIR
    local DDIR

    if [ -n "$1" ]; then
        IDIR="$(sanitycheck "$1" ne)"
    else
        IDIR="$(sanitycheck "$IMGBUILD" ne)"
    fi

    if [ -z "$ROOTSIZE" ]; then
        local ROOTSIZE
        ROOTSIZE=$((1024*1024))
    fi

    if [ -z "$DOMUSIZE" ]; then
        local DOMUSIZE
        DOMUSIZE=$((1024*1024))
    fi

    if [ -z "$BRHOSTDIR" ]; then
        local BRHOSTDIR
        BRHOSTDIR=./buildroot/output/host
    fi

    if [ ! -x "$BRHOSTDIR/bin/genimage" ]; then
        echo "Buildroot must be built before generate_disk_image command can be used" >&2
        exit 1
    fi

    BDIR="${IDIR}/root/bootfs"
    RDIR="${IDIR}/root/rootfs"
    DDIR="${IDIR}/root/domufs"

    rm -rf "$BDIR"
    mkdir -p "$BDIR"
    bootfs "$BDIR"

    rm -rf "$RDIR"
    mkdir -p "$RDIR"
    rootfs "$RDIR"

    rm -rf "$DDIR"
    mkdir -p "$DDIR"
    domufs "$DDIR"

    mkdir -p "${IDIR}/input"
    rm -f "${IDIR}/input/rootfs.ext4"
    fakeroot mke2fs -t ext4 -d "$RDIR" "${IDIR}/input/rootfs.ext4" "$ROOTSIZE"

    rm -f "${IDIR}/input/domufs.ext4"
    fakeroot mke2fs -t ext4 -d "$DDIR" "${IDIR}/input/domufs.ext4" "$DOMUSIZE"

    rm -rf "${TMPDIR}/genimage"

    LD_LIBRARY_PATH="${BRHOSTDIR}/lib" \
    PATH="${BRHOSTDIR}/bin:${BRHOSTDIR}/sbin:${PATH}" \
        genimage \
            --config ./configs/genimage-sp-distro.cfg \
            --rootpath "${IDIR}/root" \
            --inputpath "${IDIR}/input" \
            --outputpath "${IDIR}/output" \
            --tmppath "$TMPDIR/genimage"
}

function build_guest_kernels {
    local ODIR

    if [ -n "$1" ]; then
        ODIR="$(sanitycheck "$1" ne)"
    else
        ODIR="$(sanitycheck "$GKBUILD" ne)"
    fi

    case "$HYPERVISOR" in
    KVM)
        mkdir -p "${ODIR}/kvm_domu"
        compile_kernel ./linux arm64 aarch64-linux-gnu- "${ODIR}/kvm_domu" raspi4_kvm_guest_release_defconfig
    ;;
    *)
        # Atm xen buildroot uses the same kernel for host and guest
    ;;
    esac
}

function set_myids {
    MYUID="$(id -u)"
    MYGID="$(id -g)"
}

function is_mounted {
    local FLAGS
    local MOUNTED

    # Save flags
    FLAGS="$-"

    # Disable exit on status != 0 for grep
    set +e

    MOUNTED="$(mount | grep "$1")"

    # Restore flags
    if [[ "$FLAGS" =~ "e" ]]; then
        set -e
    fi

    if [ -z "$MOUNTED" ]; then
        if [ "$AUTOMOUNT" == "1" ]; then
            echo "Block device is not mounted. Automounting!" >&2
            domount
        else
            echo "Block device is not mounted." >&2
            exit 1
        fi
    fi
}

function uloopimg {
    if [ -f .mountimg ]; then
        local IMG
        IMG="$(cat .mountimg)"
        sync
        sudo kpartx -d "$IMG"
        rm -f .mountimg
    else
        echo "No image currently looped" >&2
        exit 4
    fi
}

function umountimg {
    set +e
    if [ -f .mountimg ]; then
        sudo umount "$BOOTMNT"
        sudo umount "$ROOTMNT"
        sudo umount "$DOMUMNT"
        sudo umount "${ROOTMNT}-su"
        sudo umount "${DOMUMNT}-su"
        uloopimg
    else
        echo "No image currently mounted" >&2
        exit 4
    fi
}

function loopimg {
    local KPARTXOUT

    KPARTXOUT="$(sudo kpartx -l "$1" 2> /dev/null)"

    PART1="/dev/mapper/$(grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1)"
    PART2="/dev/mapper/$(grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1)"
    PART3="/dev/mapper/$(grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1)"

    sudo kpartx -a "$1"

    echo "$1" > .mountimg
}

function create_mount_points {
    mkdir -p "$BOOTMNT"
    mkdir -p "$ROOTMNT"
    mkdir -p "${ROOTMNT}-su"
    mkdir -p "$DOMUMNT"
    mkdir -p "${DOMUMNT}-su"
}

function bind_mounts {
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${ROOTMNT}-su" "$ROOTMNT"
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${DOMUMNT}-su" "$DOMUMNT"
}

function mountimg {
    set +e

    if [ -f .mountimg ]; then
        echo "Seems that image is currently mounted, please unmount previous image (or delete .mountimg if left over)" >&2
        exit 6
    fi

    if [ -z "$1" ]; then
        echo "Please specify image file" >&2
        exit 5
    fi

    loopimg "$1"

    create_mount_points

    set_myids

    sudo mount -o "uid=${MYUID},gid=$MYGID" "$PART1" "$BOOTMNT"
    sudo mount "$PART2" "${ROOTMNT}-su"
    sudo mount "$PART3" "${DOMUMNT}-su"
    bind_mounts
}

function domount {
    local DEV

    set +e

    if [ -z "$1" ]; then
        DEV="$DEFDEV"
    else
        DEV="$1"
    fi

    if [ -f "$DEV" ]; then
        # If dev is file, mount image instead
        mountimg "$DEV"
    else
        # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
        if [[ "${DEV: -1}" =~ [0-9] ]]; then
                MIDP="p"
            else
                MIDP=""
        fi

        create_mount_points

        set_myids

        sudo mount -o "uid=${MYUID},gid=$MYGID" "${DEV}${MIDP}1" "$BOOTMNT"
        sudo mount "${DEV}${MIDP}2" "${ROOTMNT}-su"
        sudo mount "${DEV}${MIDP}3" "${DOMUMNT}-su"
        bind_mounts
    fi
}

function doumount {
    local MOUNTED

    set +e

    if [ -f .mountimg ]; then
        umountimg
        return 0
    fi

    MOUNTED="$(mount | grep "$BOOTMNT")"
    if [ -z "$MOUNTED" ]; then
        echo "Not mounted"
        exit 2
    fi

    if [ "$1" == "mark" ]; then
        echo 'THIS_IS_BOOTFS' > "${BOOTMNT}/THIS_IS_BOOTFS"
        echo 'THIS_IS_ROOTFS' > "${ROOTMNT}/THIS_IS_ROOTFS"
        echo 'THIS_IS_DOMUFS' > "${DOMUMNT}/THIS_IS_DOMUFS"
    fi
    sudo umount "$BOOTMNT"
    sudo umount "$ROOTMNT"
    sudo umount "$DOMUMNT"
    sudo umount "${ROOTMNT}-su"
    sudo umount "${DOMUMNT}-su"
    sync
}

function gen_configs {
    case "$SECURE_OS" in
    1)
        local os_opt="_secure"
    ;;
    *)
        local os_opt=""
    ;;
    esac

    case "$HYPERVISOR" in
    KVM)
        local hyp_opt="kvm"
        configs/linux/defconfig_builder.sh -t "raspi4_${hyp_opt}_guest${os_opt}_release" -k linux
    ;;
    *)
        local hyp_opt="xen"
    ;;
    esac

    configs/linux/defconfig_builder.sh -t "${PLATFORM}_${hyp_opt}${os_opt}_release" -k linux
    cp "configs/buildroot_config_${PLATFORM}_${hyp_opt}${os_opt}" buildroot/.config
}

function clone {
    git submodule init
    git submodule update -f
    cp ~/.gitconfig docker/gitconfig

    cp ubuntu_20.10-config-5.8.0-1007-raspi linux/arch/arm64/configs/ubuntu2010_defconfig
    cat xen_kernel_configs >> linux/arch/arm64/configs/ubuntu2010_defconfig

    # Needed for buildroot to be able to checkout xen branch
    pushd linux
    git checkout xen
    popd

    gen_configs
}

function uboot_src {
    mkdir -p images/xen

    cp "${IMAGES}/xen" images/xen/
    cp "$KERNEL_IMAGE" images/xen/vmlinuz

    cp "${IMAGES}/$DEVTREE" images/xen
    case "$BUILDOPT" in
    0|1)
        ubootsource > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
    ;;
    2|3)
        ubootstub > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
        ubootsource > images/xen/boot2.source
        mkimage -A arm64 -T script -C none -a 0x100000 -e 0x100000 -d images/xen/boot2.source images/xen/boot2.scr
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac
}

function bootfs {
    local BOOTFS

    if [ -z "$1" ]; then
        BOOTFS="$BOOTMNT"
        is_mounted "$BOOTMNT"
    else
        BOOTFS="$(sanitycheck "$1")"
    fi

    pushd "$BOOTFS"
    rm -rf ./*
    popd

    config_txt > "${BOOTFS}/config.txt"
    cp u-boot.bin "$BOOTFS"
    cp "$KERNEL_IMAGE" "${BOOTFS}/vmlinuz"
    case "$BUILDOPT" in
    0|1)
        cp images/xen/boot.scr "$BOOTFS"
    ;;
    2|3)
        cp images/xen/boot2.scr "$BOOTFS"
    ;;
    esac

    case "$HYPERVISOR" in
    KVM)
        # Nothing to copy at this point
    ;;
    *)
        cp "${IMAGES}/xen" "$BOOTFS"
    ;;
    esac

    cp "${IMAGES}/$DEVTREE" "$BOOTFS"
    cp -r "${IMAGES}/rpi-firmware/overlays" "$BOOTFS"
    cp usbfix/fixup4.dat "$BOOTFS"
    cp usbfix/start4.elf "$BOOTFS"
}

function netboot {
    local BOOTFS

    case "$BUILDOPT" in
    2|3)
        if [ -z "$1" ]; then
            BOOTFS="$BOOTMNT"
            is_mounted "$BOOTMNT"
        else
            BOOTFS="$(sanitycheck "$1")"
        fi

        pushd "$BOOTFS"
        rm -rf ./*
        popd

        config_txt > "${BOOTFS}/config.txt"
        cp u-boot.bin "$BOOTFS"
        cp usbfix/fixup4.dat "$BOOTFS"
        cp usbfix/start4.elf "$BOOTFS"
        cp images/xen/boot.scr "$BOOTFS"
        cp "${IMAGES}/$DEVTREE" "$BOOTFS"
    ;;
    *)
        echo "Not configured for network boot" >&2
        exit 1
    ;;
    esac
}

function rootfs {
    local ROOTFS

    if [ -z "$1" ]; then
        ROOTFS="$ROOTMNT"
        is_mounted "$ROOTMNT"
    else
        ROOTFS="$(sanitycheck "$1")"
    fi

    pushd "$ROOTFS"
    echo "Updating $ROOTFS/"
    rm -rf ./*
    fakeroot tar xf "${IMAGES}/rootfs.tar" > /dev/null
    popd

    if ! [ -a "images/rasp_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/rasp_id_rsa" -N ""
    fi

    mkdir -p "${ROOTFS}/root/.ssh"
    cat images/rasp_id_rsa.pub >> "${ROOTFS}/root/.ssh/authorized_keys"
    chmod 700 "${ROOTFS}/root/.ssh/authorized_keys"
    chmod 700 "${ROOTFS}/root/.ssh"

    dom0_interfaces > "${ROOTFS}/etc/network/interfaces"
    cp configs/wpa_supplicant.conf "${ROOTFS}/etc/wpa_supplicant.conf"

    domu_config > "${ROOTFS}/root/domu.cfg"
    case "$BUILDOPT" in
    2|3)
        net_rc_add dom0 > "${ROOTFS}/etc/init.d/S41netadditions"
        chmod 755 "${ROOTFS}/etc/init.d/S41netadditions"
        if [ "$HYPERVISOR" == "XEN" ] ; then
            echo 'vif.default.script="vif-nat"' >> "${ROOTFS}/etc/xen/xl.conf"
        fi
    ;;
    *)
    ;;
    esac

    cp buildroot/package/busybox/S10mdev "${ROOTFS}/etc/init.d/S10mdev"
    chmod 755 "${ROOTFS}/etc/init.d/S10mdev"
    cp buildroot/package/busybox/mdev.conf "${ROOTFS}/etc/mdev.conf"

    if [ "$PLATFORM" == "raspi4" ] ; then
        cp "$ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.txt" "${ROOTFS}/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt"
    fi
    inittab dom0 > "${ROOTFS}/etc/inittab"
    echo '. .bashrc' > "${ROOTFS}/root/.profile"
    echo 'PS1="\u@\h:\w# "' > "${ROOTFS}/root/.bashrc"
    echo "${RASPHN}-dom0" > "${ROOTFS}/etc/hostname"

    case "$HYPERVISOR" in
    KVM)
        case "$PLATFORM" in
        x86)
            cp "$KERNEL_IMAGE" "${ROOTFS}/root/Image"
            cp qemu/run-x86-qemu.sh "${ROOTFS}/root"
        ;;
        *)
            cp "${GKBUILD}/kvm_domu/arch/arm64/boot/Image" "${ROOTFS}/root/Image"
            cp qemu/efi-virtio.rom "${ROOTFS}/root"
            cp qemu/qemu-system-aarch64 "${ROOTFS}/root"
            cp qemu/run-qemu.sh "${ROOTFS}/root"
        ;;
        esac

        rq_sh > "${ROOTFS}/root/rq.sh"
        chmod a+x "${ROOTFS}/root/rq.sh"
    ;;
    *)
        cp "$KERNEL_IMAGE" "${ROOTFS}/root/Image"
    ;;
    esac
}

function domufs {
    local DOMUFS

    if [ -z "$1" ]; then
        DOMUFS="$DOMUMNT"
        is_mounted "$DOMUMNT"
    else
        DOMUFS="$(sanitycheck "$1")"
    fi

    rootfs "$DOMUFS"

    case "$BUILDOPT" in
    2|3)
        net_rc_add domu > "${DOMUFS}/etc/init.d/S41netadditions"
        chmod 755 "${DOMUFS}/etc/init.d/S41netadditions"
    ;;
    *)
    ;;
    esac

    domu_interfaces > "${DOMUFS}/etc/network/interfaces"
    inittab domu > "${DOMUFS}/etc/inittab"
    echo "${RASPHN}-domu" > "${DOMUFS}/etc/hostname"
}

function nfsupdate {
    case "$BUILDOPT" in
    2|3)
        set_myids
        create_mount_points
        if [ "$PLATFORM" != "x86" ] ; then
            sudo bindfs "--map=0/${MYUID}:@nogroup/@$MYGID" "$TFTPPATH" "$BOOTMNT"
        fi
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOM0" "$ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOMU" "$DOMUMNT"

        if [ "$PLATFORM" != "x86" ] ; then
            bootfs
            chmod -R 744 "$BOOTMNT"
            chmod 755 "$BOOTMNT"
            chmod 755 "${BOOTMNT}/overlays"
        fi
        rootfs
        echo "DOM0_NFSROOT" > "${ROOTMNT}/DOM0_NFSROOT"
        domufs
        echo "DOMU_NFSROOT" > "${DOMUMNT}/DOMU_NFSROOT"

        if [ "$PLATFORM" != "x86" ] ; then
            sudo umount "$BOOTMNT"
        fi
        sudo umount "$ROOTMNT"
        sudo umount "$DOMUMNT"
    ;;
    *)
        echo "BUILDOPT is not set for network boot" >&2
        exit 1
    ;;
    esac
}

# If you have changed for example linux/arch/arm64/configs/xen_defconfig and want buildroot to recompile kernel
function kernel_conf_change {
    if [ -f /usr/src/linux/.git ]; then
        pushd buildroot/dl/linux/git
        git branch --set-upstream-to=origin/xen xen
        git pull
        popd
        rm -f buildroot/dl/linux/linux*.tar.gz
        rm -rf buildroot/output/build/linux-xen
    else
        echo "This command needs to be run in the docker environment" >&2
    fi
}

function ssh_dut {
    case "$1" in
    domu)
        ssh -i images/rasp_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@$RASPIP"
    ;;
    *)
        ssh -i images/rasp_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@$RASPIP"
    esac
}

function dofsck {
    local DEV
    local MIDP

    set +e

    if [ -z "$1" ]; then
        DEV="$DEFDEV"
    else
        DEV="$1"
    fi

    if [ -f "$DEV" ]; then
        # If dev is file, get loop devices for image
        loopimg "$DEV"
    else
        # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
        if [[ "${DEV: -1}" =~ [0-9] ]]; then
                MIDP="p"
            else
                MIDP=""
        fi

        PART1="${DEV}${MIDP}1"
        PART2="${DEV}${MIDP}2"
        PART3="${DEV}${MIDP}3"
    fi

    sudo fsck.msdos "$PART1"
    sudo fsck.ext4 -f "$PART2"
    sudo fsck.ext4 -f "$PART3"

    if [ -f "$DEV" ]; then
        uloopimg
    fi
}

function buildall {
    case "$1" in
    x86|X86)
        x86config
    ;;
    kvm|KVM)
        kvmconfig
    ;;
    xen|XEN)
        defconfig
    ;;
    "")
        # Don't touch config unless explicitly told to
        # On just cloned repo Xen defaults will be used
    ;;
    *)
        echo "Invalid parameter: $1" >&2
        exit 1
    ;;
    esac

    # Reload config in case it was changed above
    . default_setup_sh_config
    . .setup_sh_config

    clone
    cd docker
    make build_env
    make ci
    cd ..
}

function showhelp {
    echo "Usage $0 <command> [parameters]"
    echo ""
    echo "Commands:"
    echo "    defconfig                         Create new .setup_sh_config from defaults"
    echo "    kvmconfig                         Create new .setup_sh_config for KVM"
    echo "    x86config                         Create new .setup_sh_config for x86"
    echo "    clone                             Clone the required subrepositories"
    echo "    mount [device|image_file]         Mount given device or image file"
    echo "    umount [mark]                     Unmount and optionally mark partitions"
    echo "    bootfs [path]                     Copy boot fs files"
    echo "    rootfs [path]                     Copy root fs files (dom0)"
    echo "    domufs [path]                     Copy domu fs files"
    echo "    fsck [device|image_file]          Check filesystems in device or image"
    echo "    uboot_src                         Generate U-boot script"
    echo "    netboot [path]                    Copy boot files needed for network boot"
    echo "    nfsupdate                         Copy boot,root and domufiles for TFTP/NFS boot"
    echo "    kernel_conf_change                Force buildroot to recompile kernel after config changes"
    echo "    ssh_dut [domu]                    Open ssh session with target device"
    echo "    buildall [xen|kvm|x86]            Builds a disk image and filesystem tarballs"
    echo "                                      uses selected default config if given"
    echo "                                      (overwrites .setup_sh_config if given)"
    echo ""
    exit 0
}

# Some translations
case "$1" in
    mount|sdcard)
        CMD="domount"
    ;;
    umount|usdcard)
        CMD="doumount"
    ;;
    domu)
        CMD="domufs"
    ;;
    fsck)
        CMD="dofsck"
    ;;
    ""|help|-h|--help)
        showhelp >&2
    ;;
    *)
        CMD="$1"
    ;;
esac

shift

# Check if function exists and run it if it does
fn_exists "$CMD"
"$CMD" "$@"
