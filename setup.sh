#!/bin/bash

function On_exit_cleanup {
    set +e
    if [ -n "$TCDIST_TMPDIR" ]; then
        rm -rf "$TCDIST_TMPDIR"
    fi
    popd > /dev/null
}

# Stop script on error
set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Save original working dir
OPWD=$PWD

# Change to the script directory and set cleanup on exit
pushd "$SDIR" > /dev/null
trap On_exit_cleanup EXIT

. helpers.sh
. text_generators.sh

function Generate_disk_image {
    local idir
    local bdir
    local rdir
    local ddir

    if [ -n "$1" ]; then
        idir="$(Sanity_check "$1" ne)"
    else
        idir="$(Sanity_check "$TCDIST_IMGBUILD" ne)"
    fi

    if [ -z "$TCDIST_ROOTSIZE" ]; then
        local TCDIST_ROOTSIZE
        TCDIST_ROOTSIZE=$((1024*1024))
    fi

    if [ -z "$TCDIST_DOMUSIZE" ]; then
        local TCDIST_DOMUSIZE
        TCDIST_DOMUSIZE=$((1024*1024))
    fi

    if [ -z "$TCDIST_BRHOSTDIR" ]; then
        local TCDIST_BRHOSTDIR
        TCDIST_BRHOSTDIR=./buildroot/output/host
    fi

    if [ "$TCDIST_ARCH" != "x86" ] && [ ! -x "$TCDIST_BRHOSTDIR/bin/genimage" ]; then
        echo "Buildroot must be built before generate_disk_image command can be used" >&2
        exit 1
    fi

    bdir="${idir}/root/bootfs"
    rdir="${idir}/root/rootfs"
    ddir="${idir}/root/domufs"

    rm -rf "$bdir"
    mkdir -p "$bdir"
    Boot_fs "$bdir"

    rm -rf "$rdir"
    mkdir -p "$rdir"
    Root_fs "$rdir"

    rm -rf "$ddir"
    mkdir -p "$ddir"
    Domu_fs "$ddir"

    mkdir -p "${idir}/input"
    rm -f "${idir}/input/rootfs.ext4"
    fakeroot mke2fs -t ext4 -d "$rdir" "${idir}/input/rootfs.ext4" "$TCDIST_ROOTSIZE"

    rm -f "${idir}/input/domufs.ext4"
    fakeroot mke2fs -t ext4 -d "$ddir" "${idir}/input/domufs.ext4" "$TCDIST_DOMUSIZE"

    if [ "$TCDIST_ARCH" = "x86" ] ; then
        return 0
    fi

    rm -rf "${TCDIST_TMPDIR}/genimage"

    LD_LIBRARY_PATH="${TCDIST_BRHOSTDIR}/lib" \
    PATH="${TCDIST_BRHOSTDIR}/bin:${TCDIST_BRHOSTDIR}/sbin:${PATH}" \
        genimage \
            --config ./configs/genimage-sp-distro.cfg \
            --rootpath "${idir}/root" \
            --inputpath "${idir}/input" \
            --outputpath "${idir}/output" \
            --tmppath "$TCDIST_TMPDIR/genimage"
}

function Build_guest_kernels {
    local odir
    local arch
    local prefix
    local os_opt

    if [ -n "$1" ]; then
        odir="$(Sanity_check "$1" ne)"
    else
        odir="$(Sanity_check "$TCDIST_GKBUILD" ne)"
    fi

    case "$TCDIST_SECUREOS" in
    1)
        os_opt="_secure"
    ;;
    *)
        os_opt=""
    ;;
    esac

    case "$TCDIST_ARCH" in
    x86)
        arch="x86_64"
        prefix="x86_64-linux-gnu-"
    ;;
    *)
        arch="arm64"
        prefix="aarch64-linux-gnu-"
    ;;
    esac

    case "$TCDIST_HYPERVISOR" in
    kvm)
        mkdir -p "${odir}/kvm_domu"
        Compile_kernel ./linux "$arch" "$prefix" "${odir}/kvm_domu" "${TCDIST_ARCH}_${TCDIST_PLATFORM}_kvm_guest${os_opt}_release_defconfig" "" "${TCDIST_LINUX_BRANCH}"
    ;;
    *)
        # Atm xen buildroot uses the same kernel for host and guest
    ;;
    esac
}

function Gen_configs {
    local os_opt

    case "$TCDIST_SECUREOS" in
    1)
        os_opt="_secure"
    ;;
    *)
        os_opt=""
    ;;
    esac

    case "$TCDIST_HYPERVISOR" in
    kvm)
        configs/linux/defconfig_builder.sh -t "${TCDIST_ARCH}_${TCDIST_PLATFORM}_${TCDIST_HYPERVISOR}_guest${os_opt}_release" -k linux
        if [ "$TCDIST_ARCH" = "x86" ] && [ "$TCDIST_SUB_ARCH" = "amd" ] ; then
            sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "linux/arch/x86/configs/${TCDIST_ARCH}_${TCDIST_PLATFORM}_${TCDIST_HYPERVISOR}_guest${os_opt}_release_defconfig"
        fi
    ;;
    *)
    ;;
    esac

    configs/linux/defconfig_builder.sh -t "${TCDIST_ARCH}_${TCDIST_PLATFORM}_${TCDIST_HYPERVISOR}${os_opt}_release" -k linux
    cp "configs/buildroot_config_${TCDIST_ARCH}_${TCDIST_PLATFORM}_${TCDIST_HYPERVISOR}${os_opt}" buildroot/.config
    if [ "$TCDIST_ARCH" = "x86" ] && [ "$TCDIST_SUB_ARCH" = "amd" ] ; then
        sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "linux/arch/x86/configs/${TCDIST_ARCH}_${TCDIST_HYPERVISOR}${os_opt}_release_defconfig"
    fi
}

function Clone {
    git submodule init
    git submodule update -f
    cp ~/.gitconfig docker/gitconfig

    cp ubuntu_20.10-config-5.8.0-1007-raspi linux/arch/arm64/configs/ubuntu2010_defconfig
    cat xen_kernel_configs >> linux/arch/arm64/configs/ubuntu2010_defconfig

    # Make sure all branches are available in linux repo
    Fetch_all linux

    # Checkout the default branch
    pushd linux
    git checkout "${TCDIST_LINUX_BRANCH}"
    popd

    Gen_configs
}

function Uboot_script {
    if [ "$TCDIST_ARCH" = "x86" ] ; then
        echo "INFO: Uboot_script generated scripts not needed for x86 build."
        return 0
    fi

    mkdir -p images/xen

    cp "${TCDIST_IMAGES}/xen" images/xen/
    cp "$TCDIST_KERNEL_IMAGE" images/xen/vmlinuz

    cp "${TCDIST_IMAGES}/$TCDIST_DEVTREE" images/xen
    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        Uboot_stub > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
        Uboot_source > images/xen/boot2.source
        mkimage -A arm64 -T script -C none -a 0x100000 -e 0x100000 -d images/xen/boot2.source images/xen/boot2.scr
    ;;
    *)
        Uboot_source > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
    ;;
    esac
}

function Boot_fs {
    local bootfs

    if [ "$TCDIST_ARCH" = "x86" ] ; then
        echo "INFO: x86 does not require bootfs setup."
        return 0
    fi

    if [ -z "$1" ]; then
        bootfs="$TCDIST_BOOTMNT"
        Is_mounted "$TCDIST_BOOTMNT"
    else
        bootfs="$(Sanity_check "$1")"
    fi

    if [ "$TCDIST_FS_UPDATE_ONLY" != "1" ] ; then
        pushd "$bootfs"
        rm -rf ./*
        popd
    fi

    Config_txt > "${bootfs}/config.txt"
    cp u-boot.bin "$bootfs"
    cp "$TCDIST_KERNEL_IMAGE" "${bootfs}/vmlinuz"
    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        cp images/xen/boot2.scr "$bootfs"
    ;;
    *)
        cp images/xen/boot.scr "$bootfs"
    ;;
    esac

    case "$TCDIST_HYPERVISOR" in
    kvm)
        # Nothing to copy at this point
    ;;
    *)
        cp "${TCDIST_IMAGES}/xen" "$bootfs"
    ;;
    esac

    cp "${TCDIST_IMAGES}/$TCDIST_DEVTREE" "$bootfs"
    cp -r "${TCDIST_IMAGES}/rpi-firmware/overlays" "$bootfs"
    cp usbfix/fixup4.dat "$bootfs"
    cp usbfix/start4.elf "$bootfs"
}

function Net_boot_fs {
    local bootfs

    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        if [ -z "$1" ]; then
            bootfs="$TCDIST_BOOTMNT"
            Is_mounted "$TCDIST_BOOTMNT"
        else
            bootfs="$(Sanity_check "$1")"
        fi

        pushd "$bootfs"
        rm -rf ./*
        popd

        Config_txt > "${bootfs}/config.txt"
        cp u-boot.bin "$bootfs"
        cp usbfix/fixup4.dat "$bootfs"
        cp usbfix/start4.elf "$bootfs"
        cp images/xen/boot.scr "$bootfs"
        cp "${TCDIST_IMAGES}/$TCDIST_DEVTREE" "$bootfs"
    ;;
    *)
        echo "Not configured for network boot" >&2
        exit 1
    ;;
    esac
}

function Root_fs {
    local rootfs

    if [ -z "$1" ]; then
        rootfs="$TCDIST_ROOTMNT"
        Is_mounted "$TCDIST_ROOTMNT"
    else
        rootfs="$(Sanity_check "$1")"
    fi

    if [ "$VDAUPDATE" != "1" ] ; then
        pushd "$rootfs"
        echo "Updating $rootfs/"
        if [ "$TCDIST_FS_UPDATE_ONLY" != "1" ] ; then
            rm -rf ./*
        fi
        fakeroot tar xf "${TCDIST_IMAGES}/rootfs.tar" > /dev/null
        popd
    fi

    if ! [ -a "images/device_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/device_id_rsa" -N ""
    fi

    mkdir -p "${rootfs}/root/.ssh"
    cat images/device_id_rsa.pub >> "${rootfs}/root/.ssh/authorized_keys"
    chmod 700 "${rootfs}/root/.ssh/authorized_keys"
    chmod 700 "${rootfs}/root/.ssh"

    Dom0_interfaces > "${rootfs}/etc/network/interfaces"
    cp configs/wpa_supplicant.conf "${rootfs}/etc/wpa_supplicant.conf"

    Net_rc_add dom0 > "${rootfs}/etc/init.d/S41netadditions"
    chmod 755 "${rootfs}/etc/init.d/S41netadditions"

    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        if [ "$TCDIST_HYPERVISOR" == "xen" ] ; then
            echo 'vif.default.script="vif-nat"' >> "${rootfs}/etc/xen/xl.conf"
        fi
    ;;
    *)
    ;;
    esac

    cp buildroot/package/busybox/S10mdev "${rootfs}/etc/init.d/S10mdev"
    chmod 755 "${rootfs}/etc/init.d/S10mdev"
    cp buildroot/package/busybox/mdev.conf "${rootfs}/etc/mdev.conf"

    if [ "$TCDIST_PLATFORM" == "raspi4" ] ; then
        cp "$rootfs/lib/firmware/brcm/brcmfmac43455-sdio.txt" "${rootfs}/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt"
    fi
    Inittab dom0 > "${rootfs}/etc/inittab"
    echo '. .bashrc' > "${rootfs}/root/.profile"
    echo 'PS1="\u@\h:\w# "' > "${rootfs}/root/.bashrc"
    echo "${TCDIST_DEVICEHN}-dom0" > "${rootfs}/etc/hostname"

    case "$TCDIST_HYPERVISOR" in
    kvm)
        case "$TCDIST_ARCH" in
        x86)
            cp "${TCDIST_GKBUILD}/kvm_domu/arch/x86/boot/bzImage" "${rootfs}/root/Image"
            #cp "$TCDIST_KERNEL_IMAGE" "${rootfs}/root/Image"
            Run_x86_qemu_sh > "${rootfs}/root/run-x86-qemu.sh"
            chmod a+x "${rootfs}/root/run-x86-qemu.sh"
        ;;
        *)
            cp "${TCDIST_GKBUILD}/kvm_domu/arch/arm64/boot/Image" "${rootfs}/root/Image"
            #cp "$TCDIST_KERNEL_IMAGE" "${rootfs}/root/Image"
            cp qemu/efi-virtio.rom "${rootfs}/root"
            cp qemu/qemu-system-aarch64 "${rootfs}/root"
            cp qemu/run-qemu.sh "${rootfs}/root"
        ;;
        esac

        Rq_sh > "${rootfs}/root/rq.sh"
        chmod a+x "${rootfs}/root/rq.sh"

        Host_socat_sh > "${rootfs}/root/host_socat.sh"
        chmod a+x "${rootfs}/root/host_socat.sh"

        Virt_socat_sh > "${rootfs}/root/virt_socat.sh"
        chmod a+x "${rootfs}/root/virt_socat.sh"
    ;;
    *)
        cp "$TCDIST_KERNEL_IMAGE" "${rootfs}/root/Image"
        Domu_config > "${rootfs}/root/domu.cfg"
    ;;
    esac
}

function Domu_fs {
    local domufs

    if [ -z "$1" ]; then
        domufs="$TCDIST_DOMUMNT"
        Is_mounted "$TCDIST_DOMUMNT"
    else
        domufs="$(Sanity_check "$1")"
    fi

    Root_fs "$domufs"

    Net_rc_add domu > "${domufs}/etc/init.d/S41netadditions"
    chmod 755 "${domufs}/etc/init.d/S41netadditions"

    Domu_interfaces > "${domufs}/etc/network/interfaces"
    Inittab domu > "${domufs}/etc/inittab"
    echo "${TCDIST_DEVICEHN}-domu" > "${domufs}/etc/hostname"

    case "$TCDIST_ARCH" in
        x86)
            rm -rf "${domufs}/lib/modules"
            mkdir -p "${domufs}/lib/modules"
            if [ "$TCDIST_SECUREOS" = "0" ] ; then
                Install_kernel_modules ./linux x86_64 x86_64-linux-gnu- "${TCDIST_GKBUILD}/kvm_domu" "${domufs}" ""
            fi
        ;;
        *)
        ;;
    esac
}

function Root_fs_e2tools {
    local rootfs

    if [ -z "$1" ]; then
        echo "Image missing"
        exit 1
    fi

    if ! [ -a "images/device_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/device_id_rsa" -N ""
    fi
    rootfs="${1}:"
    echo "Updating rootfs: ${rootfs}"

    e2mkdir  "${rootfs}/root/.ssh" -P 700 -G 0 -O 0
    e2cp images/device_id_rsa.pub "${rootfs}/root/.ssh/authorized_keys" -P 700 -G 0 -O 0

    Dom0_interfaces > tmpfile
    e2cp tmpfile "${rootfs}/etc/network/interfaces" -G 0 -O 0
    e2cp configs/wpa_supplicant.conf "${rootfs}/etc/wpa_supplicant.conf" -G 0 -O 0

    Net_rc_add dom0 > tmpfile
    e2cp tmpfile "${rootfs}/etc/init.d/S41netadditions" -P 755 -G 0 -O 0

    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        if [ "$TCDIST_HYPERVISOR" == "xen" ] ; then
            e2cp "${rootfs}/etc/xen/xl.conf" tmpfile
            echo 'vif.default.script="vif-nat"' >> tmpfile
            e2cp tmpfile "${rootfs}/etc/xen/xl.conf"
        fi
    ;;
    *)
    ;;
    esac

    e2cp buildroot/package/busybox/S10mdev "${rootfs}/etc/init.d/S10mdev" -P 755 -G 0 -O 0
    e2cp buildroot/package/busybox/mdev.conf "${rootfs}/etc/mdev.conf" -P 755 -G 0 -O 0

    if [ "$TCDIST_PLATFORM" == "raspi4" ] ; then
        e2cp "$rootfs/lib/firmware/brcm/brcmfmac43455-sdio.txt" "${rootfs}/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt"
    fi
    Inittab dom0 > tmpfile
    e2cp tmpfile "${rootfs}/etc/inittab"  -P 755 -G 0 -O 0

    echo '. .bashrc' >  tmpfile
    e2cp tmpfile "${rootfs}/root/.profile" -P 755 -G 0 -O 0
    echo 'PS1="\u@\h:\w# "' > tmpfile
    e2cp tmpfile "${rootfs}/root/.bashrc" -P 755 -G 0 -O 0
    echo "${TCDIST_DEVICEHN}-dom0" > tmpfile
    e2cp tmpfile "${rootfs}/etc/hostname" -P 755 -G 0 -O 0

    case "$TCDIST_HYPERVISOR" in
    kvm)
        case "$TCDIST_ARCH" in
        x86)
            e2cp "${TCDIST_GKBUILD}/kvm_domu/arch/x86/boot/bzImage" "${rootfs}/root/Image"
            Run_x86_qemu_sh > tmpfile
            e2cp tmpfile "${rootfs}/root/run-x86-qemu.sh" -P 777
        ;;
        *)
            e2cp "${TCDIST_GKBUILD}/kvm_domu/arch/arm64/boot/Image" "${rootfs}/root/Image"
            e2cp qemu/efi-virtio.rom "${rootfs}/root"
            e2cp qemu/qemu-system-aarch64 "${rootfs}/root"
            e2cp qemu/run-qemu.sh "${rootfs}/root"
        ;;
        esac

        Rq_sh > tmpfile
        e2cp tmpfile "${rootfs}/root/rq.sh" -P 755

        Host_socat_sh > tmpfile
        e2cp tmpfile "${rootfs}/root/host_socat.sh" -P 755

        Virt_socat_sh > tmpfile
        e2cp tmpfile "${rootfs}/root/virt_socat.sh" -P 755
    ;;
    *)
        e2cp "$TCDIST_KERNEL_IMAGE" "${rootfs}/root/Image"
        Domu_config > tmpfile
        e2cp tmpfile "${rootfs}/root/domu.cfg"
    ;;
    esac
}

function Domu_fs_e2tools {
    local domufs

    if [ -z "$1" ]; then
        echo "Image missing"
        exit 1
    fi

    domufs="$1:"
    Root_fs_e2tools "$1"

    Net_rc_add domu > tmpfile
    e2cp tmpfile "${domufs}/etc/init.d/S41netadditions" -P 755

    Domu_interfaces > tmpfile
    e2cp tmpfile "${domufs}/etc/network/interfaces"
    Inittab domu > tmpfile
    e2cp tmpfile "${domufs}/etc/inittab"
    echo "${TCDIST_DEVICEHN}-domu" > tmpfile
    e2cp tmpfile "${domufs}/etc/hostname"

    case "$TCDIST_ARCH" in
        x86)
            set +e
            # We don't want to fail if modules is already removed
            e2rm -r "${domufs}/lib/modules"
            set -e
            e2mkdir "${domufs}/lib/modules"
            # TODO: Fix this if needed
            #if [ "$TCDIST_SECUREOS" = "0" ] ; then
                #Install_kernel_modules ./linux x86_64 x86_64-linux-gnu- "${TCDIST_GKBUILD}/kvm_domu" "${domufs}" ""
            #fi
            set -e
        ;;
        *)
        ;;
    esac
}

function Nfs_update {
    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        Set_my_ids
        Create_mount_points
        if [ "$TCDIST_ARCH" != "x86" ] ; then
            sudo bindfs "--map=0/${MYUID}:@nogroup/@$MYGID" "$TCDIST_TFTPPATH" "$TCDIST_BOOTMNT"
        fi
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$TCDIST_NFSDOM0" "$TCDIST_ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$TCDIST_NFSDOMU" "$TCDIST_DOMUMNT"

        if [ "$TCDIST_ARCH" != "x86" ] ; then
            Boot_fs
            chmod -R 744 "$TCDIST_BOOTMNT"
            chmod 755 "$TCDIST_BOOTMNT"
            chmod 755 "${TCDIST_BOOTMNT}/overlays"
        fi
        Root_fs
        echo "DOM0_NFSROOT" > "${TCDIST_ROOTMNT}/DOM0_NFSROOT"
        Domu_fs
        echo "DOMU_NFSROOT" > "${TCDIST_DOMUMNT}/DOMU_NFSROOT"

        if [ "$TCDIST_SECUREOS" = "1" ] && [ "$TCDIST_ARCH" = "x86" ] ; then
            # Secure-os contains a docker installation that doesn't run
            # very well over raw NFS file system. To overcome this limitation,
            # lets create a 100M ext2 virtual disk image for it, and mount
            # it automatically
            rm -f "${TCDIST_GKBUILD}/docker.ext2"
            mkfs.ext2 -L docker-vd "${TCDIST_GKBUILD}/docker.ext2" 100M
            cp "${TCDIST_GKBUILD}/docker.ext2" "${TCDIST_ROOTMNT}/root/docker.ext2"
            if ! grep -q docker "${TCDIST_ROOTMNT}/etc/fstab"  ; then
                echo -e "/dev/vda\t/var/lib/docker\text2\tdefaults\t0\t2" >> "${TCDIST_ROOTMNT}/etc/fstab"
            fi
            if ! grep -q docker "${TCDIST_DOMUMNT}/etc/fstab" ; then
                echo -e "/dev/vda\t/var/lib/docker\text2\tdefaults\t0\t2" >> "${TCDIST_DOMUMNT}/etc/fstab"
            fi
        fi

        if [ "$TCDIST_ARCH" != "x86" ] ; then
            sudo umount "$TCDIST_BOOTMNT"
        fi
        sudo umount "$TCDIST_ROOTMNT"
        sudo umount "$TCDIST_DOMUMNT"
    ;;
    *)
        echo "TCDIST_BUILDOPT is not set for network boot: $TCDIST_BUILDOPT" >&2
        exit 1
    ;;
    esac
}

function Vdaupdate {
    local size
    local rootfs_file
    local domufs_file

    if [ "$TCDIST_ARCH" != "x86" ] ; then
        echo "VDA update is only supported for x86." >&2
        exit 1
    fi

    case "$TCDIST_BUILDOPT" in
    usb|mmc)
        # Create a copy of the rootfs.ext2 image for including domu.
        # The rootfs image gets copied inside the rootfs-withdomu.ext2
        # thus we must also double the size of rootfs-withdomu.ext2 image.
        e2fsck -y -f "${TCDIST_IMAGES}/rootfs.ext2"
        cp -f "${TCDIST_IMAGES}/rootfs.ext2" "${TCDIST_IMAGES}/rootfs-withdomu.ext2"
        size="$(wc -c "${TCDIST_IMAGES}/rootfs-withdomu.ext2" | cut -d " " -f 1)"
        size="$((size * 2 / 1024 / 1024 + 10))"
        echo "Resizing rootfs to ${size}M bytes"
        resize2fs "${TCDIST_IMAGES}/rootfs-withdomu.ext2" "${size}M"

        rootfs_file="${TCDIST_IMAGES}/rootfs-withdomu.ext2"
        domufs_file="${TCDIST_IMAGES}/rootfs.ext2"

        echo "Update image: ${rootfs_file}"

        Root_fs_e2tools "${rootfs_file}"
        echo "DOM0_VDAROOT" > tmpfile
        e2cp tmpfile "${rootfs_file}:/DOM0_VDAROOT"
        Domu_fs_e2tools "${domufs_file}"
        echo "DOMU_VDAROOT" > tmpfile
        e2cp tmpfile "${domufs_file}:/DOMU_VDAROOT"

        e2cp "${TCDIST_IMAGES}/rootfs.ext2" "${rootfs_file}:/root/rootfs.ext2"
    ;;
    *)
        echo "TCDIST_BUILDOPT is not set for VDA boot (USB/SD): $TCDIST_BUILDOPT" >&2
        exit 1
    ;;
    esac

    echo "Vdaupdate successful"
}

# If you have changed for example linux/arch/arm64/configs/xen_defconfig and want buildroot to recompile kernel
function Kernel_config_change {
    if ! In_docker; then
        echo "This command needs to be run in the docker environment" >&2
        exit 1
    fi

    if [ -f linux/.git ] && [ -d buildroot/dl/linux/git ]; then
        pushd buildroot/dl/linux/git
        git branch --set-upstream-to=origin/xen xen
        git pull
        popd
        rm -f buildroot/dl/linux/linux*.tar.gz
        rm -rf buildroot/output/build/linux-xen
    else
            echo "Linux was not cloned yet" >&2
    fi
}

function Ssh_dut {
    local dut_ip
    local subnet
    local st
    local ip
    local ips
    local vm_id
    local ssh_port

    case "$1" in
    domu)
        case "$TCDIST_ARCH" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@$TCDIST_DEVICEIP"
        ;;
        esac
    ;;
    vm_*)
        # SSH to target VM, e.g. vm_admin. The code below checks if the IP
        # address for the VM is known already (.br_admin.ip.tmp file exists),
        # and we check with ping to see if the IP address is still valid or
        # whether it has gone stale. In case we don't know the current IP
        # address for the VM, we attempt to discover it with use of NMAP
        # over the network bridge that is used for the VM network
        vm_id=$1
        case "$TCDIST_ARCH" in
        x86)
            vm_id=${vm_id/#vm_/br_}

            case "$vm_id" in
            br_secure)
                ssh_port=222
            ;;
            *)
                ssh_port=2222
            ;;
            esac

            # Check if we know VM IP address already
            if [ -f "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp" ] ; then
                dut_ip=$(cat "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp")
                set +e

                # Check if the VM responds to ping (i.e., our IP address is still valid)
                st=$(ping -c 1 -W 1 "$dut_ip" | grep "from $dut_ip")
                set -e
                if [ -z "${st}" ] ; then
                    # No response, mark our address as invalid
                    dut_ip=""
                fi
            fi
            if [ -z ${dut_ip} ] ; then
                echo "No DUT IP known, exploring..."
                rm -f "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp"

                # Generate subnet mask for our bridge, get current IP address
                # for it and grab first three values.
                subnet=$(ifconfig | grep -A 1 "$TCDIST_ADMIN_BRIDGE" | grep -o "inet [0-9\.]*" | cut -d " " -f 2 | cut -d "." -f 1-3)
                echo "Our subnet is ${subnet}.0/24"

                # Scan the generated subnet for anybody home, cut first address
                # away as that is our own address
                ips=$(nmap -sP "${subnet}.0/24" | grep "${subnet}" | tail -n +2 | grep -o "[0-9\.]*")
                set +e

                # We have a list of everybody in the subnet, now try our
                # VM SSH key against each to see which of them accepts it,
                # and run "uname -a" on them to match our target VM name.
                for ip in ${ips} ; do
                    echo "Trying IP: $ip"
                    st=$(ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p "$ssh_port" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no "root@${ip}" uname -a | grep "${vm_id}")
                    if [ -n "$st" ] ; then
                        echo "IP $ip mapped to dut"
                        dut_ip=$ip
                    fi
                done

                # Attempt localhost in case qemu is using slirp network
                st=$(ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no "root@localhost" uname -a | grep "${vm_id}")
                if [ -n "$st" ] ; then
                    echo "IP localhost mapped to dut"
                    dut_ip="localhost"
                fi
                set -e

                # Found our target IP address, save it for later use as the
                # VMs in most cases retain their IP address.
                echo "$dut_ip" > "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp"
            fi

            ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p "$ssh_port" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@${dut_ip}"
        ;;
        esac
    ;;
    *)
        case "$TCDIST_ARCH" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@$TCDIST_DEVICEIP"
        ;;
        esac
    esac
}

function Fsck {
    local dev
    local midp

    set +e

    if [ -z "$1" ]; then
        dev="$TCDIST_DEFDEV"
    else
        dev="$1"
    fi

    if [ -f "$dev" ]; then
        # If dev is file, get loop devices for image
        Loop_img "$dev"
    else
        # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
        if [[ "${dev: -1}" =~ [0-9] ]]; then
                midp="p"
            else
                midp=""
        fi

        PART1="${dev}${midp}1"
        PART2="${dev}${midp}2"
        PART3="${dev}${midp}3"
    fi

    sudo fsck.msdos "$PART1"
    sudo fsck.ext4 -f "$PART2"
    sudo fsck.ext4 -f "$PART3"

    if [ -f "$dev" ]; then
        Uloop_img
    fi
}

function Build_all {
    local noclone

    case "${1,,}" in
    x86)
        X86config
    ;;
    arm64)
        Arm64config
    ;;
    kvm)
        Kvmconfig
    ;;
    xen)
        Xenconfig
    ;;
    "")
        # Don't touch config unless explicitly told to
        # On just cloned repo Xen defaults will be used
    ;;
    noclone)
        noclone=1
    ;;
    *)
        echo "Invalid parameter: $1" >&2
        exit 1
    ;;
    esac

    # Reload config in case it was changed above
    Load_config

    if [ -z $noclone ]; then
        Clone
    fi

    make -C docker build_env
    make -C docker ci
}

# Clean up so that on next build everything gets rebuilt but nothing gets redownloaded
function Clean {
    local entry

    Safer_rmrf "$TCDIST_GKBUILD"
    Safer_rmrf "$TCDIST_IMGBUILD"
    Safer_rmrf "$TCDIST_TMPDIR"

    # Try to clean buildroot only if docker and buildroot have been cloned
    if [ -f "docker/Makefile" ] && [ -f "buildroot/Makefile" ]; then
        # Create/update build environment in any case
        make -C docker build_env
        make -C docker buildroot_clean
        # Removing kernel to force refecth from local linux kernel tree
        rm -rf buildroot/dl/linux
    fi

    # Run 'cleanup.sh clean' in subdirs, if available
    for entry in ./*/ ;do
        if [ -x "${entry}/cleanup.sh" ]; then
            "${entry}/cleanup.sh" clean "$@"
        fi
    done

    case "$1" in
    keepconfig)
        # Keeping ${TCDIST_SETUP_SH_CONFIG}
    ;;
    *)
        rm -f "${TCDIST_SETUP_SH_CONFIG}"
    ;;
    esac
}

# Restore situation before first 'setup.sh clone' but keep local main repo changes
# Removes a ton of stuff, like submodule changes, be careful
function Distclean {
    local entry

    Umount
    Remove_ignores

    # Go through the submodule dirs, remove "path = " from the start and delete & recreate dir
    while IFS= read -r entry; do
        entry="$(Trim "$entry")"
        entry="${entry#path = }"
        Safer_rmrf "$entry"
        mkdir -p "$entry"
    done <<< "$(grep "path = " .gitmodules)"

    # Run 'cleanup.sh distclean' in subdirs, if available
    for entry in ./*/ ;do
        if [ -x "${entry}/cleanup.sh" ]; then
            "$entry/cleanup.sh" distclean "$@"
        fi
    done
}

function Shell {
    if [ ! -f docker/gitconfig ]; then
        make -C docker build_env
    fi
    make -C docker shell
}

function Check_script {
    Shellcheck_bashate setup.sh helpers.sh text_generators.sh default_setup_sh_config tests/secure_os_tests.sh
}

function Show_help {
    echo "Usage $0 <command> [parameters]"
    echo ""
    echo "Commands:"
    echo "    defconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} from defaults"
    echo "    xenconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} for xen"
    echo "    kvmconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} for kvm"
    echo "    x86config                         Create new ${TCDIST_SETUP_SH_CONFIG} for x86"
    echo "    arm64config                       Create new ${TCDIST_SETUP_SH_CONFIG} for raspi4"
    echo "    arm64config_ls1012a               Create new ${TCDIST_SETUP_SH_CONFIG} for nxp ls1012a-frwy"
    echo "    clone                             Clone the required subrepositories"
    echo "    mount [device|image_file]         Mount given device or image file"
    echo "    umount [mark]                     Unmount and optionally mark partitions"
    echo "    bootfs [path]                     Copy boot fs files"
    echo "    rootfs [path]                     Copy root fs files (dom0)"
    echo "    domufs [path]                     Copy domu fs files"
    echo "    fsck [device|image_file]          Check filesystems in device or image"
    echo "    uboot_script                      Generate U-boot script"
    echo "    netboot [path]                    Copy boot files needed for network boot"
    echo "    nfsupdate                         Copy boot,root and domufiles for TFTP/NFS boot"
    echo "    vdaupdate                         Update images for x86/qemu setup"
    echo "    kernel_config_change              Force buildroot to recompile kernel after config changes"
    echo "    ssh_dut [domu]                    Open ssh session with target device"
    echo "    shell                             Open docker shell"
    echo "    buildall [xen|kvm|x86|noclone]    Builds a disk image and filesystem tarballs"
    echo "                                      uses selected default config if given"
    echo "                                      (overwrites ${TCDIST_SETUP_SH_CONFIG} if given)"
    echo "                                      noclone option skips cloning"
    echo "    build_guest_kernels               Build required guest kernels"
    echo "    distclean                         removes almost everything except main repo local changes"
    echo "                                      (basically resets to just cloned main repo)"
    echo "    clean [keepconfig]                Clean up built files, but keep downloads."
    echo "                                      Use 'keepconfig' option to preserve ${TCDIST_SETUP_SH_CONFIG}"
    echo "    check_script                      Check setup.sh script (and sourced scripts) with"
    echo "                                      shellcheck and bashate"
    echo "    install_completion                Install bash completion for setup.sh commands"
    echo ""
    exit 0
}

function Install_completion {
    echo 'complete -W "defconfig xenconfig kvmconfig x86config clone mount umount bootfs rootfs domufs fsck uboot_script netboot nfsupdate kernel_config_change ssh_dut shell buildall distclean clean check_script vdaupdate build_guest_kernels" setup.sh' | sudo tee /etc/bash_completion.d/setup.sh_completion > /dev/null
    echo "Bash auto completion installed (you need to reopen bash shell for changes to be in effect)"
}

# Convert command to all lower case and then convert first letter to upper case
CMD="${1,,}"
CMD="${CMD^}"

# Some aliases for legacy and clearer function names
case "$CMD" in
    Sdcard)
        CMD="Mount"
    ;;
    Usdcard)
        CMD="Umount"
    ;;
    Domu|Domufs)
        CMD="Domu_fs"
    ;;
    ""|Help|-h|--help)
        Load_config
        Show_help >&2
    ;;
    Uboot_src)
        CMD="Uboot_script"
    ;;
    Buildall)
        CMD="Build_all"
    ;;
    Bootfs)
        CMD="Boot_fs"
    ;;
    Rootfs)
        CMD="Root_fs"
    ;;
    Nfsupdate)
        CMD="Nfs_update"
    ;;
    Netboot)
        CMD="Net_boot_fs"
    ;;
    Defconfig)
        CMD="Xenconfig"
    ;;
    Kernel_conf_change)
        CMD="Kernel_config_change"
    ;;
    *)
        # Default, no conversion
    ;;
esac

shift

case "$CMD" in
    Xenconfig|Kvmconfig|X86config|Arm64config|Arm64config_ls1012a)
        set -a
        TCDIST_SETUP_SH_CONFIG=".setup_sh_config${TCDIST_PRODUCT}"
        set +a
        Min_config
    ;;
    Clean|Distclean)
        # Do not check config if cleaning
        Load_config nocheck
    ;;
    *)
        Load_config
    ;;
esac

# Check if function exists and run it if it does
Fn_exists "$CMD"
"$CMD" "$@"
