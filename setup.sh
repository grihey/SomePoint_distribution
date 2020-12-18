#!/bin/bash

set -e

if [ ! -f .setup_sh_config ]; then
    echo ".setup_sh_config not found, creating with defaults"
    cat << EOF > .setup_sh_config
AUTOMOUNT=0
USBBUILD=0
MNT_DIR=\`pwd\`/mnt
IMAGES=\`pwd\`/buildroot/output/images
KERNEL_IMAGE=\$IMAGES/Image
DUT_IP=192.168.1.170
EOF
fi

. .setup_sh_config

CCACHE=

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    export CCACHE_DIR=`pwd`/.ccache
    export CCACHE_MAXSIZE=10G

    #ccache -s
fi

# sanitycheck function will return the clean path or exit with an error
# usage example: CLEANPATH=`sanitycheck <path to check>`
#   on error error message is printed to stderr and CLEANPATH is empty
#   on success CLEANPATH is the cleaned up path to <path to check>
function sanitycheck {
    set +e

    local TPATH=`realpath -e $1 2>/dev/null`

    case $TPATH in
    /)
        echo "Will not touch host root directory" >&2
        exit 2
        ;;
    `pwd`)
        echo "Will not touch current directory" >&2
        exit 3
        ;;
    "")
        echo "Path does not exist" >&2
        exit 4
        ;;
    $HOME)
        echo "Will not touch user home directory" >&2
        exit 5
        ;;
    *)
        echo $TPATH
        exit 0
        ;;
    esac
}

function umountimg {
    set +e
    if [ -f .mountimg ]; then
        IMG=`cat .mountimg`
        sudo umount mnt/fat32
        sudo umount mnt/ext4
        sudo umount mnt/ext4_domu
        sudo sync
        sudo kpartx -d $IMG
        rm -f .mountimg
    else
        echo "No image currently mounted"
        exit 4
    fi
}

function mountimg {
    set +e

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
    mkdir -p $MNT_DIR/ext4_domu

    KPARTXOUT=`sudo kpartx -l $1 2> /dev/null`

    LOOP1=`grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1`
    LOOP2=`grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1`
    LOOP3=`grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1`

    sudo kpartx -a $1 2> /dev/null

    sudo mount /dev/mapper/$LOOP1 mnt/fat32
    sudo mount /dev/mapper/$LOOP2 mnt/ext4
    sudo mount /dev/mapper/$LOOP3 mnt/ext4_domu

    echo $1 > .mountimg
}


function sdcard {
    set +e

    if [ "$1x" == "x" ]; then
        SDCARD=/dev/sda
    else
        SDCARD=$1
    fi
    mkdir -p $MNT_DIR
    mkdir -p $MNT_DIR/fat32
    mkdir -p $MNT_DIR/ext4
    mkdir -p $MNT_DIR/ext4_domu
    sudo mount ${SDCARD}1 $MNT_DIR/fat32
    sudo mount ${SDCARD}2 $MNT_DIR/ext4
    sudo mount ${SDCARD}3 $MNT_DIR/ext4_domu
}

function usdcard {
    set +e

    if [ "$1" == "mark" ]; then
        echo 'THIS_IS_BOOTFS' | sudo tee -a $MNT_DIR/fat32/THIS_IS_BOOTFS > /dev/null
        echo 'THIS_IS_ROOTFS' | sudo tee -a $MNT_DIR/ext4/THIS_IS_ROOTFS > /dev/null
        echo 'THIS_IS_DOMUFS' | sudo tee -a $MNT_DIR/ext4_domu/THIS_IS_DOMUFS > /dev/null
    fi
    sudo umount $MNT_DIR/fat32
    sudo umount $MNT_DIR/ext4
    sudo umount $MNT_DIR/ext4_domu
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

function compile {
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
    pushd xen-hyp/xen
    #./configure --build=x86_64-unknown-linux-gnu --host=aarch64-linux-gnu
    make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        DESTDIR=../images/xen/ install
    popd
}

devices=("dev" "proc" "sys" "dev/pts")
function mount_chroot {
    set +e

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

function uboot_src {
    mkdir -p images/xen

    cp $IMAGES/xen images/xen/
    cp $KERNEL_IMAGE images/xen/vmlinuz

    pushd images/xen
    cp $IMAGES/bcm2711-rpi-4-b.dtb .
    if [ $USBBUILD -eq 0 ]; then
        ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config.sd -t "fatload mmc 0:1" -d .
    else
        ../../imagebuilder/scripts/uboot-script-gen -c ../../configs/uboot_config.usb -t "fatload usb 0:1" -d .
    fi
    popd
}

function is_mounted {
    #Save flags
    local FLAGS=$-

    #disable exit on status != 0 for grep
    set +e

    local MOUNTED=`mount | grep "$MNT_DIR\/$1"`

    #restore flags
    if [[ "$FLAGS" =~ "e" ]]; then
        set -e
    fi

    if [ "$MOUNTED" == "" ]; then
        if [ "$AUTOMOUNT" == "1" ]; then
            echo "Block device is not mounted. Automounting is set. Mounting!"
            sdcard
        else
            echo "Block device is not mounted."
            exit -1
        fi
    fi
}

function bootfs {
    if [ "$1x" == "x" ]; then
        BOOTFS=$MNT_DIR/fat32
        is_mounted fat32
    else
        BOOTFS=`sanitycheck $1`
    fi

    pushd $BOOTFS
    sudo rm -fr *
    popd

    sudo cp configs/config.txt $BOOTFS/
    sudo cp u-boot.bin $BOOTFS/
    sudo cp $KERNEL_IMAGE $BOOTFS/vmlinuz
    sudo cp images/xen/boot.scr $BOOTFS/boot.scr

    sudo cp $IMAGES/xen $BOOTFS/
    sudo cp -r $IMAGES/bcm2711-rpi-4-b.dtb $BOOTFS/
    sudo cp -r $IMAGES/Image $BOOTFS/vmlinuz
    sudo cp -r $IMAGES/rpi-firmware/overlays $BOOTFS/
    sudo cp usbfix/fixup4.dat $BOOTFS/
    sudo cp usbfix/start4.elf $BOOTFS/
}

function rootfs {
    if [ "$1x" == "x" ]; then
        ROOTFS=$MNT_DIR/ext4
        is_mounted ext4
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

    sudo cp configs/interfaces $ROOTFS/etc/network/interfaces
    sudo cp configs/wpa_supplicant.conf $ROOTFS/etc/wpa_supplicant.conf

    sudo cp configs/network $ROOTFS/root/
    if [ $USBBUILD -eq 0 ]; then
        sudo cp configs/domu0.cfg.sd $ROOTFS/root/domu0.cfg
    else
        sudo cp configs/domu0.cfg.usb $ROOTFS/root/domu0.cfg
    fi    
    sudo cp $KERNEL_IMAGE $ROOTFS/root/Image

    sudo cp buildroot/package/busybox/S10mdev $ROOTFS/etc/init.d/S10mdev
    sudo chmod 755 $ROOTFS/etc/init.d/S10mdev
    sudo cp buildroot/package/busybox/mdev.conf $ROOTFS/etc/mdev.conf

    sudo cp $ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.txt $ROOTFS/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt
    sudo cp configs/inittab.dom0 $ROOTFS/etc/inittab
}

function domu {
    if [ "$1x" == "x" ]; then
        DOMUFS=$MNT_DIR/ext4_domu
        is_mounted ext4_domu
    else
        DOMUFS=`sanitycheck $1`
    fi

    rootfs $DOMUFS

    sudo cp configs/inittab.domu $DOMUFS/etc/inittab
    sudo cp configs/hostname.domu $DOMUFS/etc/hostname

}

# If you have changed for example linux/arch/arm64/configs/xen_defconfig and want buildroot to recompile kernel
function kernel_conf_change {
    if [ -f /usr/src/linux/.git ]; then
        pushd buildroot/dl/linux/git
        git branch --set-upstream-to=origin/xen xen
        git pull
        popd
        rm -f buildroot/dl/linux/linux*.tar
        rm -rf buildroot/output/build/linux-xen
    else
        echo "This command needs to be run in the docker environment"
    fi
}

function ssh_dut {
    ssh -i images/rasp_id_rsa root@$DUT_IP
}

$*
