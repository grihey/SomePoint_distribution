#!/bin/bash

set -e

. helpers.sh

if [ "x$1" == "xdefconfig" ]; then
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

function domu_config {
    case $BUILDOPT in
    0)
        cat configs/domu.cfg.sd
    ;;
    1)
        cat configs/domu.cfg.usb
    ;;
    2|3)
        echo "kernel = \"/root/Image\""
        echo "cmdline = \"console=hvc0 earlyprintk=xen sync_console root=/dev/nfs rootfstype=nfs nfsroot=${NFSSERVER}:${NFSDOMU},tcp,rw,vers=3 ip=10.123.123.2::10.123.123.1:255.255.255.0:raspi-domu:eth0:off:${RASPDNS}\""
        echo "memory = \"1024\""
        echo "name = \"rpi4-xen-guest\""
        echo "vcpus = 2"
        echo "cpus = \"3-4\""
        echo "serial=\"pty\""
        echo "disk = [ 'phy:/dev/mmcblk0p3,xvda,w' ]"
        echo "vif=[ 'mac=FA:CE:C0:FF:EE:00,ip=10.123.123.2' ]"
        echo "vfb = [ 'type=vnc,vncdisplay=10,vncpasswd=raspberry' ]"
        echo "type = \"pvh\""
        echo ""
        echo "# Guest VGA console configuration, either SDL or VNC"
        echo "#sdl = 1"
        echo "vnc = 1"
    ;;
    esac
}

function dom0_interfaces {
    case $BUILDOPT in
    2)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        echo "iface eth0 inet dhcp"
        echo ""
        echo "iface default inet dhcp"
    ;;
    3)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        echo "iface eth0 inet static"
        echo "    address ${RASPIP}"
        echo "    netmask ${RASPNM}"
        echo "    gateway ${RASPGW}"
        echo ""
        echo "iface default inet dhcp"
    ;;
    *)
        cat configs/interfaces
    ;;
    esac
}

function domu_interfaces {
    case $BUILDOPT in
    2|3)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        echo "iface eth0 inet static"
        echo "    address 10.123.123.2"
        echo "    netmask 255.255.255.0"
        echo "    gateway 10.123.123.1"
        echo ""
        echo "iface default inet dhcp"
    ;;
    *)
        cat configs/interfaces
    ;;
    esac
}


function ubootstub {
    case $BUILDOPT in
    0)
        echo "fatload mmc 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    1)
        echo "fatload usb 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    2)
        echo "dhcp 0x100000 ${TFTPSERVER}:boot2.scr"
        echo "setenv serverip ${TFTPSERVER}"
        echo "source 0x100000"
    ;;
    3)
        echo "setenv ipaddr ${RASPIP}"
        echo "setenv netmask ${RASPNM}"
        echo "setenv serverip ${TFTPSERVER}"
        echo "tftp 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac
}

function ubootsource {
    case $BUILDOPT in
    0)
        local LOAD="fatload mmc 0:1"
        local BOOTARGS="dwc_otg.lpm_enable=0 console=hvc0 earlycon=xen earlyprintk=xen root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait fixrtc quiet splash"
    ;;
    1)
        local LOAD="fatload usb 0:1"
        local BOOTARGS="dwc_otg.lpm_enable=0 console=hvc0 earlycon=xen earlyprintk=xen root=/dev/sda2 rootfstype=ext4 elevator=deadline rootwait fixrtc quiet splash"
    ;;
    2|3)
        local LOAD="tftp"
        local BOOTARGS="dwc_otg.lpm_enable=0 console=hvc0 earlycon=xen earlyprintk=xen root=/dev/nfs rootfstype=nfs nfsroot=${NFSSERVER}:${NFSDOM0},tcp,rw,vers=3 ip=${IPCONFRASPI} elevator=deadline rootwait fixrtc quiet splash"
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac

    echo "setenv xen_addr E00000"
    echo "setenv lin_addr 1000000"
    echo "setenv fdt_addr 2600000"
    echo "${LOAD} 0x\${xen_addr} xen"
    echo "${LOAD} 0x\${lin_addr} vmlinuz"
    echo "setenv lin_size \$filesize"
    echo "${LOAD} 0x\${fdt_addr} bcm2711-rpi-4-b.dtb"
    echo "fdt addr \${fdt_addr}"
    echo "fdt resize 1024"
    echo "fdt set /chosen \\#address-cells <1>"
    echo "fdt set /chosen \\#size-cells <1>"
    echo "fdt set /chosen xen,xen-bootargs \"console=dtuart dtuart=serial0 sync_console dom0_mem=4G dom0_max_vcpus=2 bootscrub=0 vwfi=native sched=null\""
    echo "fdt mknod /chosen dom0"
    echo "fdt set /chosen/dom0 compatible \"xen,linux-zimage\" \"xen,multiboot-module\""
    echo "fdt set /chosen/dom0 reg <0x\${lin_addr} 0x\${lin_size}>"
    echo "fdt set /chosen xen,dom0-bootargs \"${BOOTARGS}\""
    echo "setenv fdt_high 0xffffffffffffffff"
    echo "booti 0x\${xen_addr} - 0x\${fdt_addr}"
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


function umountimg {
    set +e
    if [ -f .mountimg ]; then
        IMG=`cat .mountimg`
        sudo umount $BOOTMNT
        sudo umount $ROOTMNT
        sudo umount $DOMUMNT
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
    mkdir -p $BOOTMNT
    mkdir -p $ROOTMNT
    mkdir -p $DOMU_MNT

    KPARTXOUT=`sudo kpartx -l $1 2> /dev/null`

    LOOP1=`grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1`
    LOOP2=`grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1`
    LOOP3=`grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1`

    sudo kpartx -a $1 2> /dev/null

    sudo mount /dev/mapper/$LOOP1 $BOOTMNT
    sudo mount /dev/mapper/$LOOP2 $ROOTMNT
    sudo mount /dev/mapper/$LOOP3 $DOMUMNT

    echo $1 > .mountimg
}

function sdcard {
    set +e

    if [ "$1x" == "x" ]; then
        SDCARD=/dev/sda
    else
        SDCARD=$1
    fi

    mkdir -p $BOOTMNT
    mkdir -p $ROOTMNT
    mkdir -p $DOMUMNT
    sudo mount ${SDCARD}1 $BOOTMNT
    sudo mount ${SDCARD}2 $ROOTMNT
    sudo mount ${SDCARD}3 $DOMUMNT
}

function usdcard {
    set +e

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

devices=("dev" "proc" "sys" "dev/pts")
function mount_chroot {
    set +e

    echo "mount for chroot"
    for i in ${devices[@]}; do
        mount -o bind /$i $ROOTMNT/$i
    done
}

function umount_chroot {
    echo "umount chroot"
    #Unmounting needs to be done in reverse order (otherwise umount of dev is tried before dev/pts)
    for ((j=${#devices[@]}-1; j>=0; j--)); do
        umount $ROOTMNT/${devices[$j]}
    done
}

function update {
    mounted=`mount | grep $BOOTMNT`
    if ! [ "$mounted" != "" ];
    then
        echo "Boot partition not mounted"
        exit -1
    fi

    is_root=`whoami`
    if [ "$is_root" != "root" ];
    then
        echo "Run update command with sudo rights"
        exit 1
    fi

    echo "Copying libs.."
    cp -r images/modules/lib/* $ROOTMNT/lib/

    echo "Copying dtbs.."
    cp linux/arch/arm64/boot/dts/broadcom/*.dtb $BOOTMNT/
    cp linux/arch/arm64/boot/dts/overlays/*.dtb* $BOOTMNT/overlays/
    cp linux/arch/arm64/boot/dts/overlays/README $BOOTMNT/overlays/
    echo "Copying vmlinuz"
    cp images/boot/vmlinuz-5.9.6+ $BOOTMNT/vmlinuz
    cp images/boot/* $ROOTMNT/boot/
    echo "Copying USB boot fixes"
    cp usbfix/start4.elf usbfix/fixup4.dat $BOOTMNT/
    cp usbfix/start4.elf usbfix/fixup4.dat $ROOTMNT/boot

    mount_chroot
cat << EOF | chroot $ROOTMNT
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
    if [ "$1x" == "x" ]; then
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
    if [ "$1x" == "x" ]; then
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
    if [ "$1x" == "x" ]; then
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
        sudo cp configs/S41ipforward $ROOTFS/etc/init.d/
        sudo chmod 755 $ROOTFS/etc/init.d/S41ipforward
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
}

function domu {
    if [ "$1x" == "x" ]; then
        DOMUFS=$DOMUMNT
        is_mounted $DOMUMNT
    else
        DOMUFS=`sanitycheck $1`
    fi

    rootfs $DOMUFS

    domu_interfaces | sudo tee $DOMUFS/etc/network/interfaces > /dev/null
    sudo cp configs/inittab.domu $DOMUFS/etc/inittab
    sudo cp configs/hostname.domu $DOMUFS/etc/hostname

}

function nfsupdate {
    case $BUILDOPT in
    2|3)
        bootfs "$TFTPPATH"
        rootfs "$NFSDOM0"
        domu "$NFSDOMU"
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
        rm -f buildroot/dl/linux/linux*.tar
        rm -rf buildroot/output/build/linux-xen
    else
        echo "This command needs to be run in the docker environment"
    fi
}

function ssh_dut {
    ssh -i images/rasp_id_rsa root@$RASPIP
}

fn_exists $1
$*
