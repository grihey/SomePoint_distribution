#!/bin/bash

set -e

. helpers.sh
. text_generators.sh

if [ "$1" == "defconfig" ]; then
    defconfig
    exit 0
else
    if [ ! -f .setup_sh_config ]; then
        echo ".setup_sh_config not found" >&2
        defconfig
    fi
fi

# load defaults in case .setup_sh_config is missing any settings
# for example .setup_sh_config could be from older revision
. default_setup_sh_config
. .setup_sh_config
set_ipconfraspi

CCACHE=

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    export CCACHE_DIR=`pwd`/.ccache
    export CCACHE_MAXSIZE=10G

    #ccache -s
fi

function set_myids {
    MYUID=`id -u`
    MYGID=`id -g`
}

function is_mounted {
    #Save flags
    local FLAGS=$-

    #disable exit on status != 0 for grep
    set +e

    local MOUNTED=`mount | grep "$1"`

    #restore flags
    if [[ "$FLAGS" =~ "e" ]]; then
        set -e
    fi

    if [ -z "$MOUNTED" ]; then
        if [ "$AUTOMOUNT" == "1" ]; then
            echo "Block device is not mounted. Automounting is set. Mounting!" >&2
            domount
        else
            echo "Block device is not mounted." >&2
            exit -1
        fi
    fi
}

function uloopimg {
    if [ -f .mountimg ]; then
        IMG=`cat .mountimg`
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
    local KPARTXOUT=`sudo kpartx -l "$1" 2> /dev/null`

    PART1=/dev/mapper/`grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1`
    PART2=/dev/mapper/`grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1`
    PART3=/dev/mapper/`grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1`

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
    set +e

    if [ -z "$1" ]; then
        DEV="$DEFDEV"
    else
        DEV="$1"
    fi

    if [ -f "$DEV" ]; then
        #If dev is file, mount image instead
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
    set +e

    if [ -f .mountimg ]; then
        umountimg
        return 0
    fi

    local MOUNTED=`mount | grep "$BOOTMNT"`
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
    ;;
    *)
        local hyp_opt="xen"
    ;;
    esac

    configs/linux/defconfig_builder.sh -t "raspi4_${hyp_opt}${os_opt}_release" -k linux
    cp "configs/buildroot_config_${hyp_opt}${os_opt}" buildroot/.config
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
    if [ -z "$1" ]; then
        BOOTFS="$BOOTMNT"
        is_mounted "$BOOTMNT"
    else
        BOOTFS=`sanitycheck "$1"`
    fi

    pushd "$BOOTFS"
    rm -fr *
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
    case "$BUILDOPT" in
    2|3)
        if [ -z "$1" ]; then
            BOOTFS="$BOOTMNT"
            is_mounted "$BOOTMNT"
        else
            BOOTFS=`sanitycheck "$1"`
        fi

        pushd "$BOOTFS"
        rm -fr *
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
    if [ -z "$1" ]; then
        ROOTFS="$ROOTMNT"
        is_mounted "$ROOTMNT"
    else
        ROOTFS=`sanitycheck "$1"`
    fi

    pushd "$ROOTFS"
    echo "Updating $ROOTFS/"
    rm -fr *
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
        echo 'vif.default.script="vif-nat"' >> "${ROOTFS}/etc/xen/xl.conf"
    ;;
    *)
    ;;
    esac

    cp "$KERNEL_IMAGE" "${ROOTFS}/root/Image"

    cp buildroot/package/busybox/S10mdev "${ROOTFS}/etc/init.d/S10mdev"
    chmod 755 "${ROOTFS}/etc/init.d/S10mdev"
    cp buildroot/package/busybox/mdev.conf "${ROOTFS}/etc/mdev.conf"

    cp "$ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.txt" "${ROOTFS}/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt"
    inittab dom0 > "${ROOTFS}/etc/inittab"
    echo '. .bashrc' > "${ROOTFS}/root/.profile"
    echo 'PS1="\u@\h:\w# "' > "${ROOTFS}/root/.bashrc"
    echo "${RASPHN}-dom0" > "${ROOTFS}/etc/hostname"
}

function domufs {
    if [ -z "$1" ]; then
        DOMUFS="$DOMUMNT"
        is_mounted "$DOMUMNT"
    else
        DOMUFS=`sanitycheck "$1"`
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
        sudo bindfs "--map=0/${MYUID}:@nogroup/@$MYGID" "$TFTPPATH" "$BOOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOM0" "$ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOMU" "$DOMUMNT"

        bootfs
        chmod -R 744 "$BOOTMNT"
        chmod 755 "$BOOTMNT"
        chmod 755 "${BOOTMNT}/overlays"
        rootfs
        echo "DOM0_NFSROOT" > "${ROOTMNT}/DOM0_NFSROOT"
        domufs
        echo "DOMU_NFSROOT" > "${DOMUMNT}/DOMU_NFSROOT"

        sudo umount "$BOOTMNT"
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
        ssh -i images/rasp_id_rsa -p 222 "root@$RASPIP"
    ;;
    *)
        ssh -i images/rasp_id_rsa "root@$RASPIP"
    esac
}

function dofsck {
    set +e

    if [ -z "$1" ]; then
        DEV="$DEFDEV"
    else
        DEV="$1"
    fi

    if [ -f "$DEV" ]; then
        #If dev is file, get loop devices for image
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

function showhelp {
    echo "Usage $0 <command> [parameters]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "    defconfig                         Create new .setup_sh_config from defaults" >&2
    echo "    clone                             Clone the required subrepositories" >&2
    echo "    mount [device|image_file]         Mount given device or image file" >&2
    echo "    umount [mark]                     Unmount and optionally mark partitions" >&2
    echo "    bootfs [path]                     Copy boot fs files" >&2
    echo "    rootfs [path]                     Copy root fs files (dom0)" >&2
    echo "    domufs [path]                     Copy domu fs files" >&2
    echo "    fsck [device|image_file]          Check filesystems in device or image" >&2
    echo "    uboot_src                         Generate U-boot script" >&2
    echo "    netboot [path]                    Copy boot files needed for network boot" >&2
    echo "    nfsupdate                         Copy boot,root and domufiles for TFTP/NFS boot" >&2
    echo "    kernel_conf_change                Force buildroot to recompile kernel after config changes" >&2
    echo "    ssh_dut                           Open ssh session with target device" >&2
    echo "" >&2
    exit 0
}

# Some translations
if [ -z "$1" ]; then
    CMD="showhelp"
else
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
            CMD="showhelp"
        ;;
        *)
            CMD="$1"
        ;;
    esac

    shift
fi

#Check if function exists and run it if it does
fn_exists "$CMD"
"$CMD" $*
