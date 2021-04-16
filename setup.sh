#!/bin/bash

function On_exit_cleanup {
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
        idir="$(Sanity_check "$IMGBUILD" ne)"
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

    if [ "$PLATFORM" != "x86" ] && [ ! -x "$BRHOSTDIR/bin/genimage" ]; then
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
    fakeroot mke2fs -t ext4 -d "$rdir" "${idir}/input/rootfs.ext4" "$ROOTSIZE"

    rm -f "${idir}/input/domufs.ext4"
    fakeroot mke2fs -t ext4 -d "$ddir" "${idir}/input/domufs.ext4" "$DOMUSIZE"

    if [ "$PLATFORM" = "x86" ] ; then
        return 0
    fi

    rm -rf "${TMPDIR}/genimage"

    LD_LIBRARY_PATH="${BRHOSTDIR}/lib" \
    PATH="${BRHOSTDIR}/bin:${BRHOSTDIR}/sbin:${PATH}" \
        genimage \
            --config ./configs/genimage-sp-distro.cfg \
            --rootpath "${idir}/root" \
            --inputpath "${idir}/input" \
            --outputpath "${idir}/output" \
            --tmppath "$TMPDIR/genimage"
}

function Build_guest_kernels {
    local odir
    local arch
    local prefix
    local os_opt

    if [ -n "$1" ]; then
        odir="$(Sanity_check "$1" ne)"
    else
        odir="$(Sanity_check "$GKBUILD" ne)"
    fi

    case "$SECURE_OS" in
    1)
        os_opt="_secure"
    ;;
    *)
        os_opt=""
    ;;
    esac

    case "$PLATFORM" in
    x86)
        arch="x86_64"
        prefix="x86_64-linux-gnu-"
    ;;
    *)
        arch="arm64"
        prefix="aarch64-linux-gnu-"
    ;;
    esac

    case "$HYPERVISOR" in
    kvm)
        mkdir -p "${odir}/kvm_domu"
        Compile_kernel ./linux "$arch" "$prefix" "${odir}/kvm_domu" "${PLATFORM}_kvm_guest${os_opt}_release_defconfig"
    ;;
    *)
        # Atm xen buildroot uses the same kernel for host and guest
    ;;
    esac
}

function Gen_configs {
    local os_opt

    case "$SECURE_OS" in
    1)
        os_opt="_secure"
    ;;
    *)
        os_opt=""
    ;;
    esac

    case "$HYPERVISOR" in
    kvm)
        configs/linux/defconfig_builder.sh -t "${PLATFORM}_kvm_guest${os_opt}_release" -k linux
        if [ "$PLATFORM" = "x86" ] && [ "$SUB_PLATFORM" = "amd" ] ; then
            sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "linux/arch/x86/configs/${PLATFORM}_kvm_guest${os_opt}_release_defconfig"
        fi
    ;;
    *)
    ;;
    esac

    configs/linux/defconfig_builder.sh -t "${PLATFORM}_${HYPERVISOR}${os_opt}_release" -k linux
    cp "configs/buildroot_config_${PLATFORM}_${HYPERVISOR}${os_opt}" buildroot/.config
    if [ "$PLATFORM" = "x86" ] && [ "$SUB_PLATFORM" = "amd" ] ; then
        sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "linux/arch/x86/configs/${PLATFORM}_${HYPERVISOR}${os_opt}_release_defconfig"
    fi
}

function Clone {
    git submodule init
    git submodule update -f
    cp ~/.gitconfig docker/gitconfig

    cp ubuntu_20.10-config-5.8.0-1007-raspi linux/arch/arm64/configs/ubuntu2010_defconfig
    cat xen_kernel_configs >> linux/arch/arm64/configs/ubuntu2010_defconfig

    # Needed for buildroot to be able to checkout xen branch
    pushd linux
    git checkout xen
    popd

    Gen_configs
}

function Uboot_script {
    if [ "$PLATFORM" = "x86" ] ; then
        echo "INFO: Uboot_script generated scripts not needed for x86 build."
        return 0
    fi

    mkdir -p images/xen

    cp "${IMAGES}/xen" images/xen/
    cp "$KERNEL_IMAGE" images/xen/vmlinuz

    cp "${IMAGES}/$DEVTREE" images/xen
    case "$BUILDOPT" in
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

    if [ "$PLATFORM" = "x86" ] ; then
        echo "INFO: x86 does not require bootfs setup."
        return 0
    fi

    if [ -z "$1" ]; then
        bootfs="$BOOTMNT"
        Is_mounted "$BOOTMNT"
    else
        bootfs="$(Sanity_check "$1")"
    fi

    if [ "$FS_UPDATE_ONLY" != "1" ] ; then
        pushd "$bootfs"
        rm -rf ./*
        popd
    fi

    Config_txt > "${bootfs}/config.txt"
    cp u-boot.bin "$bootfs"
    cp "$KERNEL_IMAGE" "${bootfs}/vmlinuz"
    case "$BUILDOPT" in
    dhcp|static)
        cp images/xen/boot2.scr "$bootfs"
    ;;
    *)
        cp images/xen/boot.scr "$bootfs"
    ;;
    esac

    case "$HYPERVISOR" in
    kvm)
        # Nothing to copy at this point
    ;;
    *)
        cp "${IMAGES}/xen" "$bootfs"
    ;;
    esac

    cp "${IMAGES}/$DEVTREE" "$bootfs"
    cp -r "${IMAGES}/rpi-firmware/overlays" "$bootfs"
    cp usbfix/fixup4.dat "$bootfs"
    cp usbfix/start4.elf "$bootfs"
}

function Net_boot_fs {
    local bootfs

    case "$BUILDOPT" in
    dhcp|static)
        if [ -z "$1" ]; then
            bootfs="$BOOTMNT"
            Is_mounted "$BOOTMNT"
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
        cp "${IMAGES}/$DEVTREE" "$bootfs"
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
        rootfs="$ROOTMNT"
        Is_mounted "$ROOTMNT"
    else
        rootfs="$(Sanity_check "$1")"
    fi

    if [ "$VDAUPDATE" != "1" ] ; then
        pushd "$rootfs"
        echo "Updating $rootfs/"
        if [ "$FS_UPDATE_ONLY" != "1" ] ; then
            rm -rf ./*
        fi
        fakeroot tar xf "${IMAGES}/rootfs.tar" > /dev/null
        popd
    fi

    if ! [ -a "images/device_id_rsa" ]; then
        echo "Generate ssh key"
        ssh-keygen -t rsa -q -f "images/device_id_rsa" -N ""
        # Just to make CI build happy for now, will be removed later
        cp -pf "images/device_id_rsa" "images/rasp_id_rsa"
        cp -pf "images/device_id_rsa.pub" "images/rasp_id_rsa.pub"
    fi

    mkdir -p "${rootfs}/root/.ssh"
    cat images/device_id_rsa.pub >> "${rootfs}/root/.ssh/authorized_keys"
    chmod 700 "${rootfs}/root/.ssh/authorized_keys"
    chmod 700 "${rootfs}/root/.ssh"

    Dom0_interfaces > "${rootfs}/etc/network/interfaces"
    cp configs/wpa_supplicant.conf "${rootfs}/etc/wpa_supplicant.conf"

    Net_rc_add dom0 > "${rootfs}/etc/init.d/S41netadditions"
    chmod 755 "${rootfs}/etc/init.d/S41netadditions"

    case "$BUILDOPT" in
    dhcp|static)
        if [ "$HYPERVISOR" == "xen" ] ; then
            echo 'vif.default.script="vif-nat"' >> "${rootfs}/etc/xen/xl.conf"
        fi
    ;;
    *)
    ;;
    esac

    cp buildroot/package/busybox/S10mdev "${rootfs}/etc/init.d/S10mdev"
    chmod 755 "${rootfs}/etc/init.d/S10mdev"
    cp buildroot/package/busybox/mdev.conf "${rootfs}/etc/mdev.conf"

    if [ "$PLATFORM" == "raspi4" ] ; then
        cp "$rootfs/lib/firmware/brcm/brcmfmac43455-sdio.txt" "${rootfs}/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt"
    fi
    Inittab dom0 > "${rootfs}/etc/inittab"
    echo '. .bashrc' > "${rootfs}/root/.profile"
    echo 'PS1="\u@\h:\w# "' > "${rootfs}/root/.bashrc"
    echo "${DEVICEHN}-dom0" > "${rootfs}/etc/hostname"

    case "$HYPERVISOR" in
    kvm)
        case "$PLATFORM" in
        x86)
            cp "${GKBUILD}/kvm_domu/arch/x86/boot/bzImage" "${rootfs}/root/Image"
            #cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
            Run_x86_qemu_sh > "${rootfs}/root/run-x86-qemu.sh"
            chmod a+x "${rootfs}/root/run-x86-qemu.sh"
        ;;
        *)
            cp "${GKBUILD}/kvm_domu/arch/arm64/boot/Image" "${rootfs}/root/Image"
            #cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
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
        cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
        Domu_config > "${rootfs}/root/domu.cfg"
    ;;
    esac
}

function Domu_fs {
    local domufs

    if [ -z "$1" ]; then
        domufs="$DOMUMNT"
        Is_mounted "$DOMUMNT"
    else
        domufs="$(Sanity_check "$1")"
    fi

    Root_fs "$domufs"

    Net_rc_add domu > "${domufs}/etc/init.d/S41netadditions"
    chmod 755 "${domufs}/etc/init.d/S41netadditions"

    Domu_interfaces > "${domufs}/etc/network/interfaces"
    Inittab domu > "${domufs}/etc/inittab"
    echo "${DEVICEHN}-domu" > "${domufs}/etc/hostname"
}

function Nfs_update {
    case "$BUILDOPT" in
    dhcp|static)
        Set_my_ids
        Create_mount_points
        if [ "$PLATFORM" != "x86" ] ; then
            sudo bindfs "--map=0/${MYUID}:@nogroup/@$MYGID" "$TFTPPATH" "$BOOTMNT"
        fi
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOM0" "$ROOTMNT"
        sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "$NFSDOMU" "$DOMUMNT"

        if [ "$PLATFORM" != "x86" ] ; then
            Boot_fs
            chmod -R 744 "$BOOTMNT"
            chmod 755 "$BOOTMNT"
            chmod 755 "${BOOTMNT}/overlays"
        fi
        Root_fs
        echo "DOM0_NFSROOT" > "${ROOTMNT}/DOM0_NFSROOT"
        Domu_fs
        echo "DOMU_NFSROOT" > "${DOMUMNT}/DOMU_NFSROOT"

        if [ "$PLATFORM" != "x86" ] ; then
            sudo umount "$BOOTMNT"
        fi
        sudo umount "$ROOTMNT"
        sudo umount "$DOMUMNT"
    ;;
    *)
        echo "BUILDOPT is not set for network boot: $BUILDOPT" >&2
        exit 1
    ;;
    esac
}

function Vdaupdate {
    local size

    if [ "$PLATFORM" != "x86" ] ; then
        echo "VDA update is only supported for x86." >&2
        exit 1
    fi

    case "$BUILDOPT" in
    usb|mmc)
        Set_my_ids
        Create_mount_points

        # Create a copy of the rootfs.ext2 image for including domu.
        # The rootfs image gets copied inside the rootfs-withdomu.ext2
        # thus we must also double the size of rootfs-withdomu.ext2 image.
        e2fsck -f "${IMAGES}/rootfs.ext2"
        cp -f "${IMAGES}/rootfs.ext2" "${IMAGES}/rootfs-withdomu.ext2"
        size="$(wc -c "${IMAGES}/rootfs-withdomu.ext2" | cut -d " " -f 1)"
        size="$((size * 2 / 1024 / 1024 + 10))"
        echo "Resizing rootfs to ${size}M bytes"
        resize2fs "${IMAGES}/rootfs-withdomu.ext2" "${size}M"

        sudo mount "${IMAGES}/rootfs-withdomu.ext2" "${ROOTMNT}-su"
        sudo mount "${IMAGES}/rootfs.ext2" "${DOMUMNT}-su"
        Bind_mounts

        VDAUPDATE=1

        Root_fs
        echo "DOM0_VDAROOT" > "${ROOTMNT}/DOM0_VDAROOT"
        Domu_fs
        echo "DOMU_VDAROOT" > "${DOMUMNT}/DOMU_VDAROOT"

        sudo umount "$DOMUMNT"
        sudo umount "${DOMUMNT}-su"

        cp "${IMAGES}/rootfs.ext2" "${ROOTMNT}/root/rootfs.ext2"
        sudo umount "$ROOTMNT"
        sudo umount "${ROOTMNT}-su"
    ;;
    *)
        echo "BUILDOPT is not set for VDA boot (USB/SD): $BUILDOPT" >&2
        exit 1
    ;;
    esac

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
    case "$1" in
    domu)
        case "$PLATFORM" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@$DEVICEIP"
        ;;
        esac
    ;;
    *)
        case "$PLATFORM" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@$DEVICEIP"
        ;;
        esac
    esac
}

function Fsck {
    local dev
    local midp

    set +e

    if [ -z "$1" ]; then
        dev="$DEFDEV"
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
    kvm)
        Kvmconfig
    ;;
    xen)
        Defconfig
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
    cd docker
    make build_env
    make ci
    cd ..
}

# Clean up so that on next build everything gets rebuilt but nothing gets redownloaded
function Clean {
    local entry

    Safer_rmrf "$GKBUILD"
    Safer_rmrf "$IMGBUILD"
    Safer_rmrf "$TMPDIR"

    # Try to clean buildroot only if docker and buildroot have been cloned
    if [ -f "docker/Makefile" ] && [ -f "buildroot/Makefile" ]; then
        (
            cd docker
            # Create/update build environment in any case
            make build_env
            make buildroot_clean
        )
        (
            cd buildroot
            # Removing kernel to force refecth from local linux kernel tree
            rm -rf dl/linux
        )
    fi

    # Run 'cleanup.sh clean' in subdirs, if available
    for entry in ./*/ ;do
        if [ -x "${entry}/cleanup.sh" ]; then
            "${entry}/cleanup.sh" clean "$@"
        fi
    done

    case "$1" in
    keepconfig)
        # Keeping .setup_sh_config
    ;;
    *)
        rm -f .setup_sh_config
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
    cd docker
    if [ ! -f ./gitconfig ]; then
        make build_env
    fi
    make shell
    cd ..
}

function Check_script {
    Shellcheck_bashate setup.sh helpers.sh text_generators.sh default_setup_sh_config
}

function Show_help {
    echo "Usage $0 <command> [parameters]"
    echo ""
    echo "Commands:"
    echo "    defconfig                         Create new .setup_sh_config from defaults"
    echo "    xenconfig                         Create new .setup_sh_config for xen"
    echo "    kvmconfig                         Create new .setup_sh_config for kvm"
    echo "    x86config                         Create new .setup_sh_config for x86"
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
    echo "    kernel_config_change              Force buildroot to recompile kernel after config changes"
    echo "    ssh_dut [domu]                    Open ssh session with target device"
    echo "    shell                             Open docker shell"
    echo "    buildall [xen|kvm|x86|noclone]    Builds a disk image and filesystem tarballs"
    echo "                                      uses selected default config if given"
    echo "                                      (overwrites .setup_sh_config if given)"
    echo "                                      noclone option skips cloning"
    echo "    distclean                         removes almost everything except main repo local changes"
    echo "                                      (basically resets to just cloned main repo)"
    echo "    clean [keepconfig]                Clean up built files, but keep downloads."
    echo "                                      Use 'keepconfig' option to preserve .setup_sh_config"
    echo "    check_script                      Check setup.sh script (and sourced scripts) with"
    echo "                                      shellcheck and bashate"
    echo "    install_completion                Install bash completion for setup.sh commands"
    echo ""
    exit 0
}

function Install_completion {
    echo 'complete -W "defconfig xenconfig kvmconfig x86config clone mount umount bootfs rootfs domufs fsck uboot_script netboot nfsupdate kernel_config_change ssh_dut shell buildall distclean clean check_script" setup.sh' | sudo tee /etc/bash_completion.d/setup.sh_completion > /dev/null
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
    Xenconfig|Kvmconfig|X86config)
        # Do not load config when generating new one.
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
