#!/bin/bash

#set -x

if [ "$AUTOMOUNT" == "" ];
then
    AUTOMOUNT=0
else
    AUTOMOUNT=1
fi


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

function umountimg {
    if [ -f .mountimg ]; then
	IMG=`cat .mountimg`
	sudo umount mnt/fat32
	sudo umount mnt/ext4
	sudo sync
	sudo kpartx -d $IMG
	rm -f .mountimg
    else
	echo "No image currently mounted"
	exit 4
    fi
}

function mountimg {

    if [ -f .mountimg ]; then
        echo "Seems that image is currently mounted, please unmount previous image (or delete .mountimg if left over)"
	exit 6
    fi

    if [ "$1x" == "x" ]; then
	echo Please specify image file
	exit 5
    fi

    mkdir -p $MNT_DIR
    mkdir -p $MNT_DIR/fat32
    mkdir -p $MNT_DIR/ext4

    KPARTXOUT=`sudo kpartx -l $1 2> /dev/null`

    LOOP1=`grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1`
    LOOP2=`grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1`

    sudo kpartx -a $1 2> /dev/null

    sudo mount /dev/mapper/$LOOP1 mnt/fat32
    sudo mount /dev/mapper/$LOOP2 mnt/ext4

    echo $1 > .mountimg
}


function sdcard {
    if [ "$1x" == "x" ]; then
	SDCARD=/dev/sda
    else
	SDCARD=$1
    fi
    mkdir -p $MNT_DIR
    mkdir -p $MNT_DIR/fat32
    mkdir -p $MNT_DIR/ext4
    sudo mount ${SDCARD}1 $MNT_DIR/fat32
    sudo mount ${SDCARD}2 $MNT_DIR/ext4
}

function usdcard {
    sudo umount $MNT_DIR/fat32
    sudo umount $MNT_DIR/ext4
    sync
}

function clone {
    set -e

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

function compile {
    set -e

    mkdir -p images/boot
    pushd linux

    # RUN in docker
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- ubuntu2010_defconfig
    make -j 8 ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" Image modules dtbs
    make ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" INSTALL_MOD_PATH=../images/modules modules_install
    make ARCH=arm64 CROSS_COMPILE="${CCACHE} aarch64-linux-gnu-" INSTALL_PATH=../images/boot install
    # RUN in docker end

    popd # linux
}

function compile_xen {
    set -e

    pushd xen-hyp/xen
    #./configure --build=x86_64-unknown-linux-gnu --host=aarch64-linux-gnu
    make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        DESTDIR=../images/xen/ install
    popd
}

devices=("dev" "proc" "sys" "dev/pts")
function mount_chroot {
    echo "mount for chroot"
    for i in ${devices[@]}; do
        mount -o bind /$i $MNT_DIR/ext4/$i
    done
}

function umount_chroot {
    echo "umount chroot"
    #Unmounting needs to be done in reverse order (otherwise umount of dev is tried before dev/pts)
    for ((j=${#devices[@]}-1; j>=0; j--)); do
        umount $MNT_DIR/ext4/${devices[$j]}
    done
}

function update {
    set -e

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
    echo "Copying USB boot fixes"
    cp usbfix/start4.elf usbfix/fixup4.dat $MNT_DIR/fat32/
    cp usbfix/start4.elf usbfix/fixup4.dat $MNT_DIR/ext4/boot

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

#KERNEL_IMAGE=images/boot/vmlinuz-5.9.6+
IMAGES=`pwd`/buildroot/output/images
KERNEL_IMAGE=$IMAGES/Image

function uboot_src {
    set -e

    mkdir -p images/xen

    cp $IMAGES/xen images/xen/
    cp $KERNEL_IMAGE images/xen/vmlinuz

    pushd images/xen
    cp $IMAGES/bcm2711-rpi-4-b.dtb .
    ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config -t "fatload mmc 0:1" -d .
    popd
}

# call set -e after this
function is_mounted {
    mounted=`mount | grep "mnt\/ext4"`
    if [ "$mounted" == "" ];
    then
        if [ "$AUTOMOUNT" == "1" ];
        then
            echo "Block device is not mounted. Automounting is set. Mounting!"
            sdcard
        else
            echo "Block device is not mounted."
            exit -1
        fi
    fi
}

function bootfs {
    is_mounted

    set -e

    mounted=`mount |grep mnt\/fat32`
    if ! [ "$mounted" != "" ];
    then
        echo "Sdcard not mounted"
        exit -1
    fi

    pushd $MNT_DIR/fat32/
    sudo rm -fr *
    popd

    sudo cp configs/config.txt $MNT_DIR/fat32/
    sudo cp u-boot.bin $MNT_DIR/fat32/
    sudo cp $KERNEL_IMAGE $MNT_DIR/fat32/vmlinuz
    pushd images/xen
    sudo cp boot.scr $MNT_DIR/fat32/boot.scr
    popd

    sudo cp $IMAGES/xen $MNT_DIR/fat32/
    sudo cp -r $IMAGES/bcm2711-rpi-4-b.dtb $MNT_DIR/fat32/
    sudo cp -r $IMAGES/Image $MNT_DIR/fat32/vmlinuz
    sudo cp -r $IMAGES/rpi-firmware/overlays $MNT_DIR/fat32/
    sudo cp $IMAGES/rpi-firmware/fixup.dat $MNT_DIR/fat32/
    sudo cp $IMAGES/rpi-firmware/start.elf $MNT_DIR/fat32/
    sudo cp $IMAGES/rpi-firmware/cmdline.txt $MNT_DIR/fat32/

}

function rootfs {
    is_mounted

    # set exit on error here. grep causes error if text not found
    set -e

    pushd $MNT_DIR/ext4/
    echo "Updating $MNT_DIR/ext4/"
    sudo rm -fr *
    sudo tar xvf $IMAGES/rootfs.tar > /dev/null
    popd

    if ! [ -a "images/rasp_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/rasp_id_rsa" -N ""
    fi

    sudo mkdir -p $MNT_DIR/ext4/root/.ssh
    cat images/rasp_id_rsa.pub | sudo tee -a $MNT_DIR/ext4/root/.ssh/authorized_keys > /dev/null
    sudo chmod 600 $MNT_DIR/ext4/root/.ssh/authorized_keys
    sudo chmod 600 $MNT_DIR/ext4/root/.ssh

    sudo cp configs/interfaces $MNT_DIR/ext4/etc/network/interfaces
    sudo cp configs/wpa_supplicant.conf $MNT_DIR/ext4/etc/wpa_supplicant.conf
    #sudo cp configs/modules $MNT_DIR/ext4/etc/modules
    #sudo cp configs/loadmodules.sh $MNT_DIR/ext4/etc/init.d/S35modules

    sudo cp $KERNEL_IMAGE $MNT_DIR/ext4/root/Image

    sudo cp buildroot/package/busybox/S10mdev $MNT_DIR/ext4/etc/init.d/S10mdev
    sudo chmod 755 $MNT_DIR/ext4/etc/init.d/S10mdev
    sudo cp buildroot/package/busybox/mdev.conf $MNT_DIR/ext4/etc/mdev.conf
}

if [ "$DUT_IP" == "" ];
then
    DUT_IP=192.168.1.170
fi
function ssh_dut {
    ssh -i images/rasp_id_rsa root@$DUT_IP
}

$*
