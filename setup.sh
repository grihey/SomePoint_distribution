#!/bin/bash

set -e

. helpers.sh
. text_generators

if [ "$1" == "defconfig" ]; then
    defconfig
    exit 0
else
    if [ ! -f .setup_sh_config ]; then
        echo ".setup_sh_config not found"
        defconfig
    fi
fi

# load defaults in case .setup_sh_config is missing any settings
# for example .setup_sh_config could be from older revision
. default_setup_sh_config
. .setup_sh_config

CCACHE=

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    export CCACHE_DIR=`pwd`/.ccache
    export CCACHE_MAXSIZE=10G

    #ccache -s
fi

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
            echo "Block device is not mounted. Automounting is set. Mounting!"
            domount
        else
            echo "Block device is not mounted."
            exit -1
        fi
    fi
}

function uloopimg {
    if [ -f .mountimg ]; then
        IMG=`cat .mountimg`
        sudo sync
        sudo kpartx -d $IMG
        rm -f .mountimg
    else
        echo "No image currently looped"
        exit 4
    fi
}

function umountimg {
    set +e
    if [ -f .mountimg ]; then
        sudo umount $BOOTMNT
        sudo umount $ROOTMNT
        sudo umount $DOMUMNT
        uloopimg
    else
        echo "No image currently mounted"
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

function mountimg {
    set +e

    if [ -f .mountimg ]; then
        echo "Seems that image is currently mounted, please unmount previous image (or delete .mountimg if left over)"
        exit 6
    fi

    if [ -z "$1" ]; then
        echo Please specify image file
        exit 5
    fi

    mkdir -p $BOOTMNT
    mkdir -p $ROOTMNT
    mkdir -p $DOMUMNT

    loopimg "$1"

    sudo mount $PART1 $BOOTMNT
    sudo mount $PART2 $ROOTMNT
    sudo mount $PART3 $DOMUMNT
}

function domount {
    set +e

    if [ -z "$1" ]; then
        DEV=$DEFDEV
    else
        DEV=$1
    fi

    if [ -f $DEV ]; then
        #If dev is file, mount image instead
        mountimg $DEV
    else
        # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
        if [[ "${DEV: -1}" =~ [0-9] ]]; then
                MIDP="p"
            else
                MIDP=""
        fi

        mkdir -p $BOOTMNT
        mkdir -p $ROOTMNT
        mkdir -p $DOMUMNT
        sudo mount ${DEV}${MIDP}1 $BOOTMNT
        sudo mount ${DEV}${MIDP}2 $ROOTMNT
        sudo mount ${DEV}${MIDP}3 $DOMUMNT
    fi
}

function doumount {
    set +e

    if [ -f .mountimg ]; then
        umountimg
        return 0
    fi

    local MOUNTED=`mount | grep "$BOOTMNT"`
    if [ "x$MOUNTED" == "x" ]; then
        echo "Not mounted"
        exit 2
    fi

    if [ "$1" == "mark" ]; then
        echo 'THIS_IS_BOOTFS' | sudo tee $BOOTMNT/THIS_IS_BOOTFS > /dev/null
        echo 'THIS_IS_ROOTFS' | sudo tee $ROOTMNT/THIS_IS_ROOTFS > /dev/null
        echo 'THIS_IS_DOMUFS' | sudo tee $DOMUMNT/THIS_IS_DOMUFS > /dev/null
    fi
    sudo umount $BOOTMNT
    sudo umount $ROOTMNT
    sudo umount $DOMUMNT
    sync
}

function clone {
    git submodule init
    git submodule update -f
    cp ~/.gitconfig docker/gitconfig

    cp ubuntu_20.10-config-5.8.0-1007-raspi linux/arch/arm64/configs/ubuntu2010_defconfig
    cat xen_kernel_configs >> linux/arch/arm64/configs/ubuntu2010_defconfig

    cp buildroot_config buildroot/.config

    # Needed for buildroot to be able to checkout xen branch
    pushd linux
    git checkout xen
    popd
}

function uboot_src {
    mkdir -p images/xen

    cp $IMAGES/xen images/xen/
    cp $KERNEL_IMAGE images/xen/vmlinuz

    cp $IMAGES/bcm2711-rpi-4-b.dtb images/xen
    case $BUILDOPT in
    0)
        pushd images/xen
        ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config.sd -t "fatload mmc 0:1" -d .
        popd
    ;;
    1)
        pushd images/xen
        ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config.usb -t "fatload usb 0:1" -d .
        popd
    ;;
    2|3)
        ubootstub > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
        ubootsource > images/xen/boot2.source
        mkimage -A arm64 -T script -C none -a 0x100000 -e 0x100000 -d images/xen/boot2.source images/xen/boot2.scr
    ;;
    *)
        echo "Invalid BUILDOPT setting"
        exit 1
    ;;
    esac
}

function bootfs {
    if [ -z "$1" ]; then
        BOOTFS=$BOOTMNT
        is_mounted $BOOTMNT
    else
        BOOTFS=`sanitycheck $1`
    fi

    pushd $BOOTFS
    sudo rm -fr *
    popd

    sudo cp configs/config.txt $BOOTFS/
    sudo cp u-boot.bin $BOOTFS/
    sudo cp $KERNEL_IMAGE $BOOTFS/vmlinuz
    sudo cp images/xen/boot*.scr $BOOTFS
    sudo cp $IMAGES/xen $BOOTFS/
    sudo cp $IMAGES/bcm2711-rpi-4-b.dtb $BOOTFS/
    sudo cp -r $IMAGES/rpi-firmware/overlays $BOOTFS/
    sudo cp usbfix/fixup4.dat $BOOTFS/
    sudo cp usbfix/start4.elf $BOOTFS/
}

function netboot {
    if [ -z "$1" ]; then
        BOOTFS=$BOOTMNT
        is_mounted $BOOTMNT
    else
        BOOTFS=`sanitycheck $1`
    fi

    pushd $BOOTFS
    sudo rm -fr *
    popd

    sudo cp configs/config.txt $BOOTFS/
    sudo cp u-boot.bin $BOOTFS/
    sudo cp usbfix/fixup4.dat $BOOTFS/
    sudo cp usbfix/start4.elf $BOOTFS/
    sudo cp images/xen/boot.scr $BOOTFS/
    sudo cp $IMAGES/bcm2711-rpi-4-b.dtb $BOOTFS/
}

function rootfs {
    if [ -z "$1" ]; then
        ROOTFS=$ROOTMNT
        is_mounted $ROOTMNT
    else
        ROOTFS=`sanitycheck $1`
    fi

    pushd $ROOTFS
    echo "Updating $ROOTFS/"
    sudo rm -fr *
    sudo tar xvf $IMAGES/rootfs.tar > /dev/null
    popd

    if ! [ -a "images/rasp_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/rasp_id_rsa" -N ""
    fi

    sudo mkdir -p $ROOTFS/root/.ssh
    cat images/rasp_id_rsa.pub | sudo tee -a $ROOTFS/root/.ssh/authorized_keys > /dev/null
    sudo chmod 600 $ROOTFS/root/.ssh/authorized_keys
    sudo chmod 600 $ROOTFS/root/.ssh

    dom0_interfaces | sudo tee $ROOTFS/etc/network/interfaces > /dev/null
    sudo cp configs/wpa_supplicant.conf $ROOTFS/etc/wpa_supplicant.conf

    domu_config | sudo tee $ROOTFS/root/domu.cfg > /dev/null
    case $BUILDOPT in
    2|3)
        net_rc_add dom0 | sudo tee $ROOTFS/etc/init.d/S41netadditions > /dev/null
        sudo chmod 755 $ROOTFS/etc/init.d/S41netadditions
        echo 'vif.default.script="vif-nat"' | sudo tee -a $ROOTFS/etc/xen/xl.conf > /dev/null
    ;;
    *)
    ;;
    esac

    sudo cp $KERNEL_IMAGE $ROOTFS/root/Image

    sudo cp buildroot/package/busybox/S10mdev $ROOTFS/etc/init.d/S10mdev
    sudo chmod 755 $ROOTFS/etc/init.d/S10mdev
    sudo cp buildroot/package/busybox/mdev.conf $ROOTFS/etc/mdev.conf

    sudo cp $ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.txt $ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
    sudo cp configs/inittab.dom0 $ROOTFS/etc/inittab
    echo '. .bashrc' | sudo tee $ROOTFS/root/.profile > /dev/null
    echo 'PS1="\u@\h:\w# "' | sudo tee $ROOTFS/root/.bashrc > /dev/null
    echo "${RASPHN}-dom0" | sudo tee $ROOTFS/etc/hostname > /dev/null
}

function domufs {
    if [ -z "$1" ]; then
        DOMUFS=$DOMUMNT
        is_mounted $DOMUMNT
    else
        DOMUFS=`sanitycheck $1`
    fi

    rootfs $DOMUFS

    case $BUILDOPT in
    2|3)
        net_rc_add domu | sudo tee $DOMUFS/etc/init.d/S41netadditions > /dev/null
        sudo chmod 755 $DOMUFS/etc/init.d/S41netadditions
    ;;
    *)
    ;;
    esac

    domu_interfaces | sudo tee $DOMUFS/etc/network/interfaces > /dev/null
    sudo cp configs/inittab.domu $DOMUFS/etc/inittab
    echo "${RASPHN}-domu" | sudo tee $DOMUFS/etc/hostname > /dev/null
}

function nfsupdate {
    case $BUILDOPT in
    2|3)
        bootfs "$TFTPPATH"
        rootfs "$NFSDOM0"
        echo "DOM0_NFSROOT" | sudo tee $NFSDOM0/DOM0_NFSROOT > /dev/null
        domu "$NFSDOMU"
        echo "DOMU_NFSROOT" | sudo tee $NFSDOMU/DOMU_NFSROOT > /dev/null
    ;;
    *)
        echo "BUILDOPT is not set for network boot"
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
        echo "This command needs to be run in the docker environment"
    fi
}

function ssh_dut {
    case "$1" in
    domu)
        ssh -i images/rasp_id_rsa -p 222 root@$RASPIP
    ;;
    *)
        ssh -i images/rasp_id_rsa root@$RASPIP
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
    *)
        CMD="$1"
    ;;
esac

shift

#Check if function exists and run it if it does
fn_exists $CMD
$CMD $*
