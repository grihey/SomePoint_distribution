#!/bin/bash

#set -x

CCACHE=

if ! [ -x "$(command -v ccache)" ]; then
    echo 'Info: ccache is not installed.' >&2
else
    CCACHE="ccache"
    export CCACHE_DIR=`pwd`/.ccache
    export CCACHE_MAXSIZE=10G

    ccache -s
fi

MNT_DIR=`pwd`/mnt


function sdcard {
    mkdir -p $MNT_DIR
    mkdir -p $MNT_DIR/fat32
    mkdir -p $MNT_DIR/ext4
    sudo mount /dev/sda1 $MNT_DIR/fat32
    sudo mount /dev/sda2 $MNT_DIR/ext4
}

function usdcard {
    sync
    sudo umount $MNT_DIR/fat32
    sudo umount $MNT_DIR/ext4
}

function clone {
    git clone git@github.com:tiiuae/docker.git
    git clone https://gitlab.com/ViryaOS/imagebuilder.git
    git clone git@github.com:raspberrypi/linux.git
    pushd linux
    git checkout -b origin/rpi-5.9.y
    popd
    cp ubuntu_20.10-config-5.8.0-1007-raspi linux/arch/arm64/configs/ubuntu2010_defconfig
    cat xen_kernel_configs >> linux/arch/arm64/configs/ubuntu2010_defconfig
}

function compile {
    pushd linux

    # RUN in docker
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ubuntu2010_defconfig
    make -j 8 ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" Image modules dtbs
    make ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" INSTALL_MOD_PATH=../images/modules modules_install
    make ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" INSTALL_PATH=../images/boot install
    # RUN in docker end

    popd # linux
}

devices="dev proc sys dev/pts"
function mount_chroot {
    echo "nount for chroot"
    for i in $devices
    do
        mount -o bind /$i $MNT_DIR/ext4/$i
    done
}

function umount_chroot {
    echo "umount chroot"
    for i in $devices
    do
        umount $MNT_DIR/ext4/$i
    done
}

function update {
    mounted=`mount |grep mnt\/fat32`
    if ! [ "$mounted" != "" ];
    then
        echo "Sdcard not mounted"
        exit -1
    fi

    is_root=`whoami`
    if [ "$is_root" != "root" ];
    then
        echo "Run update command with sudo rights"
        exit 1
    fi

    echo "Copying libs.."
    cp -r images/modules/lib/* $MNT_DIR/ext4/lib/

    echo "Copying dtbs.."
    cp linux/arch/arm64/boot/dts/broadcom/*.dtb $MNT_DIR/fat32/
    cp linux/arch/arm64/boot/dts/overlays/*.dtb* $MNT_DIR/fat32/overlays/
    cp linux/arch/arm64/boot/dts/overlays/README $MNT_DIR/fat32/overlays/
    echo "Copying vmlinuz"
    cp images/boot/vmlinuz-5.9.6+ $MNT_DIR/fat32/vmlinuz

    cp images/boot/* $MNT_DIR/ext4/boot/

    mount_chroot
cat << EOF | chroot $MNT_DIR/ext4
set -x
update-initramfs -c -t -k "5.9.6+"
EOF
#
    umount_chroot

    echo "Syncing.."
    sync
}

function uboot_src {
    cp xen images/xen/
    pushd images/xen
    cp ../../linux/arch/arm64/boot/dts/broadcom/bcm2711-rpi-4-b.dtb .
    cp ../boot/vmlinuz-5.9.6+ vmlinuz
    ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config -t "fatload mmc 0:1" -d .
    popd
}

function uboot_update {
    mounted=`mount |grep mnt\/fat32`
    if ! [ "$mounted" != "" ];
    then
        echo "Sdcard not mounted"
        exit -1
    fi
    cp configs/config.txt $MNT_DIR/fat32/
    cp u-boot.bin $MNT_DIR/fat32/
    pushd images/xen
    cp xen $MNT_DIR/fat32/
    cp boot.scr $MNT_DIR/fat32/boot.scr
    popd
}


$1
