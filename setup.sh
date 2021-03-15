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

Load_config

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

    if [ "$PLATFORM" = "x86" ] ; then
        echo "INFO: x86 does not require separate guest kernel images."
        return 0
    fi

    if [ -n "$1" ]; then
        odir="$(Sanity_check "$1" ne)"
    else
        odir="$(Sanity_check "$GKBUILD" ne)"
    fi

    case "$HYPERVISOR" in
    KVM)
        # Atm kvm buildroot uses the same kernel for host and guest, uncomment
        # below to build separate guest kernel
        # mkdir -p "${odir}/kvm_domu"
        # Compile_kernel ./linux arm64 aarch64-linux-gnu- "${odir}/kvm_domu" raspi4_kvm_guest_release_defconfig

        # Workaround for shellcheck nagging about unused odir, remove this if you take above code into use
        echo "$odir" > /dev/null
    ;;
    *)
        # Atm xen buildroot uses the same kernel for host and guest
    ;;
    esac
}

function Set_my_ids {
    MYUID="$(id -u)"
    MYGID="$(id -g)"
}

function Is_mounted {
    local flags
    local mounted

    # Save flags
    flags="$-"

    # Disable exit on status != 0 for grep
    set +e

    mounted="$(mount | grep "$1")"

    # Restore flags
    if [[ "$flags" =~ "e" ]]; then
        set -e
    fi

    if [ -z "$mounted" ]; then
        if [ "$AUTOMOUNT" == "1" ]; then
            echo "Block device is not mounted. Automounting!" >&2
            Mount
        else
            echo "Block device is not mounted." >&2
            exit 1
        fi
    fi
}

function Uloop_img {
    local img

    if [ -f .mountimg ]; then
        img="$(cat .mountimg)"
        sync
        sudo kpartx -d "$img"
        rm -f .mountimg
    else
        echo "No image currently looped" >&2
        exit 4
    fi
}

function Umount_img {
    set +e
    if [ -f .mountimg ]; then
        sudo umount "$BOOTMNT"
        sudo umount "$ROOTMNT"
        sudo umount "$DOMUMNT"
        sudo umount "${ROOTMNT}-su"
        sudo umount "${DOMUMNT}-su"
        Uloop_img
    else
        echo "No image currently mounted" >&2
        exit 4
    fi
}

function Loop_img {
    local kpartxout

    kpartxout="$(sudo kpartx -l "$1" 2> /dev/null)"

    PART1="/dev/mapper/$(grep "p1 " <<< "$kpartxout" | cut -d " " -f1)"
    PART2="/dev/mapper/$(grep "p2 " <<< "$kpartxout" | cut -d " " -f1)"
    PART3="/dev/mapper/$(grep "p3 " <<< "$kpartxout" | cut -d " " -f1)"

    sudo kpartx -a "$1"

    echo "$1" > .mountimg
}

function Create_mount_points {
    mkdir -p "$BOOTMNT"
    mkdir -p "$ROOTMNT"
    mkdir -p "${ROOTMNT}-su"
    mkdir -p "$DOMUMNT"
    mkdir -p "${DOMUMNT}-su"
}

function Bind_mounts {
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${ROOTMNT}-su" "$ROOTMNT"
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${DOMUMNT}-su" "$DOMUMNT"
}

function Mount_img {
    set +e

    if [ -f .mountimg ]; then
        echo "Seems that image is currently mounted, please unmount previous image (or delete .mountimg if left over)" >&2
        exit 6
    fi

    if [ -z "$1" ]; then
        echo "Please specify image file" >&2
        exit 5
    fi

    Loop_img "$1"

    Create_mount_points

    Set_my_ids

    sudo mount -o "uid=${MYUID},gid=$MYGID" "$PART1" "$BOOTMNT"
    sudo mount "$PART2" "${ROOTMNT}-su"
    sudo mount "$PART3" "${DOMUMNT}-su"
    Bind_mounts
}

function Mount {
    local dev
    local midp

    set +e

    if [ -z "$1" ]; then
        dev="$DEFDEV"
    else
        dev="$1"
    fi

    if [ -f "$dev" ]; then
        # If dev is file, mount image instead
        Mount_img "$dev"
    else
        # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
        if [[ "${dev: -1}" =~ [0-9] ]]; then
            midp="p"
        else
            midp=""
        fi

        Create_mount_points

        Set_my_ids

        sudo mount -o "uid=${MYUID},gid=$MYGID" "${dev}${midp}1" "$BOOTMNT"
        sudo mount "${dev}${midp}2" "${ROOTMNT}-su"
        sudo mount "${dev}${midp}3" "${DOMUMNT}-su"
        Bind_mounts
    fi
}

function Umount {
    local mounted

    set +e

    if [ -f .mountimg ]; then
        Umount_img
        return 0
    fi

    mounted="$(mount | grep "$BOOTMNT")"
    if [ -z "$mounted" ]; then
        return 0
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

function Gen_configs {
    local os_opt
    local hyp_opt

    case "$SECURE_OS" in
    1)
        os_opt="_secure"
    ;;
    *)
        os_opt=""
    ;;
    esac

    case "$HYPERVISOR" in
    KVM)
        hyp_opt="kvm"
        # For now, we use same config for the guest kernels also
        #configs/linux/defconfig_builder.sh -t "raspi4_${hyp_opt}_guest${os_opt}_release" -k linux
    ;;
    *)
        hyp_opt="xen"
    ;;
    esac

    configs/linux/defconfig_builder.sh -t "${PLATFORM}_${hyp_opt}${os_opt}_release" -k linux
    cp "configs/buildroot_config_${PLATFORM}_${hyp_opt}${os_opt}" buildroot/.config
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
    0|1|MMC|USB)
        Uboot_source > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
    ;;
    2|3)
        Uboot_stub > images/xen/boot.source
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d images/xen/boot.source images/xen/boot.scr
        Uboot_source > images/xen/boot2.source
        mkimage -A arm64 -T script -C none -a 0x100000 -e 0x100000 -d images/xen/boot2.source images/xen/boot2.scr
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
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
    0|1|MMC|USB)
        cp images/xen/boot.scr "$bootfs"
    ;;
    2|3)
        cp images/xen/boot2.scr "$bootfs"
    ;;
    esac

    case "$HYPERVISOR" in
    KVM)
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
    2|3)
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

    Domu_config > "${rootfs}/root/domu.cfg"

    Net_rc_add dom0 > "${rootfs}/etc/init.d/S41netadditions"
    chmod 755 "${rootfs}/etc/init.d/S41netadditions"

    case "$BUILDOPT" in
    2|3)
        if [ "$HYPERVISOR" == "XEN" ] ; then
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
    KVM)
        case "$PLATFORM" in
        x86)
            cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
            Run_x86_qemu_sh > "${rootfs}/root/run-x86-qemu.sh"
            chmod a+x "${rootfs}/root/run-x86-qemu.sh"
        ;;
        *)
            #cp "${GKBUILD}/kvm_domu/arch/arm64/boot/Image" "${rootfs}/root/Image"
            cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
            cp qemu/efi-virtio.rom "${rootfs}/root"
            cp qemu/qemu-system-aarch64 "${rootfs}/root"
            cp qemu/run-qemu.sh "${rootfs}/root"
        ;;
        esac

        Rq_sh > "${rootfs}/root/rq.sh"
        chmod a+x "${rootfs}/root/rq.sh"
    ;;
    *)
        cp "$KERNEL_IMAGE" "${rootfs}/root/Image"
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
    2|3)
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
        echo "BUILDOPT is not set for network boot" >&2
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
    0|1|MMC|USB)
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
        echo "BUILDOPT is not set for VDA boot (USB/SD)" >&2
        exit 1
    ;;
    esac

}

# If you have changed for example linux/arch/arm64/configs/xen_defconfig and want buildroot to recompile kernel
function Kernel_conf_change {
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

function Ssh_dut {
    case "$1" in
    domu)
        ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@$DEVICEIP"
    ;;
    *)
        ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@$DEVICEIP"
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
    case "$1" in
    x86|X86)
        X86config
    ;;
    kvm|KVM)
        Kvmconfig
    ;;
    xen|XEN)
        Defconfig
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
    Load_config

    Clone
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
            # If build_env has not been run, then run it
            if [ ! -f gitconfig ]; then
                make build_env
            fi
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
            "${entry}/cleanup.sh" clean
        fi
    done
    rm -f .setup_sh_config
}

# Restore situation before first 'setup.sh clone' but keep local main repo changes
# Removes a ton of stuff, like submodule changes, be careful
function Distclean {
    local entry

    Umount
    Remove_ignores ""

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
            "$entry/cleanup.sh" distclean
        fi
    done
}

function Check_script {
    shellcheck setup.sh helpers.sh text_generators.sh default_setup_sh_config
    # Ignore "E006 Line too long" errors
    bashate -i E006 setup.sh helpers.sh text_generators.sh default_setup_sh_config
    echo Nothing to complain
}

function Show_help {
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
    echo "    distclean                         removes almost everything except main repo local changes"
    echo "                                      (basically resets to just cloned main repo)"
    echo "    clean                             Clean up built files, but keep downloads"
    echo "    check_script                      Check setup.sh script with shellcheck and bashate"
    echo ""
    exit 0
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
    *)
        # Default, no conversion
    ;;
esac

shift

# Check if function exists and run it if it does
Fn_exists "$CMD"
"$CMD" "$@"
