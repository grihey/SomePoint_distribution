#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh

# Set exit on error, so shellcheck won't suggest '|| exit 1' everywhere
set -e

# Get actual directory of this bash script
HDIR="$(dirname "${BASH_SOURCE[0]}")"
HDIR="$(realpath "$HDIR")"

# Loads build system configurations
# Disable complaints about arguments they are optional here
# shellcheck disable=SC2120
function Load_config {
    # Load defaults in case .setup_sh_config is missing any settings
    # for example .setup_sh_config could be from older revision
    # shellcheck source=./default_setup_sh_config
    . "${HDIR}/default_setup_sh_config"

    if [ -f "${HDIR}/.setup_sh_config" ]; then
        # disable shellchecking of .setup_sh_config and warnings about it
        # shellcheck disable=SC1091,SC1090
        . "${HDIR}/.setup_sh_config"
    fi

    # Convert some options to lower case
    PLATFORM="${PLATFORM,,}"
    HYPERVISOR="${HYPERVISOR,,}"
    BUILDOPT="${BUILDOPT,,}"
    SUDOTYPE="${SUDOTYPE,,}"

    if [ "$1" != "nocheck" ]; then
        case "$PLATFORM" in
        raspi4|x86)
            # Options ok
        ;;
        *)
            echo "Invalid PLATFORM: $PLATFORM" >&2
            exit 1
        ;;
        esac

        case "$HYPERVISOR" in
        xen|kvm)
            # Options ok
        ;;
        *)
            echo "Invalid HYPERVISOR: $HYPERVISOR" >&2
            exit 1
        ;;
        esac

        case "$BUILDOPT" in
        usb|mmc|dhcp|static)
            # Options ok
        ;;
        *)
            echo "Invalid BUILDOPT: $BUILDOPT" >&2
            exit 1
        esac

        case "$SUDOTYPE" in
        standard)
            # Disable sudo function if standard sudo is requested
            unset sudo
        ;;
        showonpassword|verbose|confirm)
            # Options ok
        ;;
        *)
            echo "Invalid SUDOTYPE: $SUDOTYPE" >&2
            exit 1
        ;;
        esac
    fi

    export CCACHE
    export CCACHE_DIR
    export CCACHE_MAXSIZE

    Set_deviceipconf
}

# Get path to sudo binary (or empty if not available, but don't fail here)
SUDOCMD="$(command -v sudo || true)"

# sudo function will show the command about to be run if password is prompted for
# if SUDOTYPE=verbose then all commands will be shown
# if SUDOTYPE=confirm then all commands will be confirmed regardless of password prompting
# if left in the confirm prompt for a long time, then sudo might ask password again after confirmation, but it is what it is
# sudo function meant to replace sudo command, so it is not capitalized like other functions
function sudo {
    local prompt
    local inp

    prompt="$(printf "About to sudo: \"%s\"" "$*")"

    # Check if sudo is going to ask password or not
    if "${SUDOCMD:?}" -n true 2> /dev/null; then
        case "$SUDOTYPE" in
        confirm)
            # Ask for confirmation if confirm mode enabled
            inp="x"
            while [ "$inp" == "x" ]; do
                printf "%s\nConfirm (Y/n): " "$prompt" > /dev/tty
                read -r inp < /dev/tty
                case "$inp" in
                ""|y|Y)
                    inp="Y"
                ;;
                n|N)
                    return 1
                ;;
                *)
                    echo "Invalid input" > /dev/tty
                    inp="x"
                ;;
                esac
            done
        ;;
        verbose)
            # Show the command in verbose mode
            printf "sudo: \"%s\"\n" "$*"
        ;;
        esac

        "${SUDOCMD:?}" "$@"
    else
        # If sudo is going to ask password show the command about to be run anyway
        printf "%s\n" "$prompt" > /dev/tty
        "${SUDOCMD:?}" "$@"
    fi
}

function Xenconfig {
    echo "Creating .setup_sh_config with xen configuration" >&2
    cp -f default_setup_sh_config .setup_sh_config
}

function Kvmconfig {
    echo "Creating .setup_sh_config with kvm configuration" >&2
    # Change HYPERVISOR option to kvm
    sed "s/^HYPERVISOR=.*/HYPERVISOR=kvm/" < default_setup_sh_config > .setup_sh_config
}

function X86config {
    echo "Creating .setup_sh_config for x86" >&2
    # Change several options for x86 build
    sed -e "s/^HYPERVISOR=.*/HYPERVISOR=kvm/" \
        -e "s/^PLATFORM=.*/PLATFORM=x86/" \
        -e "s/^BUILDOPT=.*/BUILDOPT=dhcp/" \
        -e "s/^KERNEL_IMAGE=.*/KERNEL_IMAGE=\$IMAGES\/bzImage/" \
        -e "s/^DEVICEHN=.*/DEVICEHN=x86/" < default_setup_sh_config > .setup_sh_config
}

# Returns 0 if function exists, 1 if not
function Fn_exists {
    if [ "$(LC_ALL=C type -t "$1")" == "function" ]; then
        return 0
    else
        echo "$1: Unknown function" >&2
        return 1
    fi
}

# Calculates actual number of bytes from strings like '4G' and '23M' plain numbers are sectors (512 bytes)
function Actual_value {
    local lch

    lch="${1: -1}"
    case "$lch" in
    G)
        echo "$((${1:0:-1}*1024*1024*1024))"
    ;;
    M)
        echo "$((${1:0:-1}*1024*1024))"
    ;;
    0|1|2|3|4|5|6|7|8|9)
        echo "$((${1}*512))"
    ;;
    *)
        echo "0"
    ;;
    esac
}

# Trims off whitespace from start and end of a string
function Trim {
    local str

    str="$*"

    # remove whitespace from start
    str="${str#"${str%%[![:space:]]*}"}"

    # remove whitespace from end
    str="${str%"${str##*[![:space:]]}"}"

    printf '%s' "$str"
}

# Slightly safer recursive deletion
# If second parameter is 'sudo' root user is used to remove files
function Safer_rmrf {
    local rmd

    # Sanity check the path, just in case
    rmd="$(Sanity_check "$1" ne)"
    if [  "$2" == "sudo" ]; then
        # Check that we actually have something to delete before using sudo
        if [ -e "${rmd:?}" ]; then
            sudo rm -rf "${rmd:?}"
        fi
    else
        rm -rf "${rmd:?}"
    fi
}

# Remove files and directories listed in .gitignores
# Disable complaints about arguments they are optional here
# shellcheck disable=SC2120
function Remove_ignores {
    local entry

    if [ -f .gitignore ]; then
        while IFS= read -r entry; do
            entry="$(Trim "$entry")"
            if [ -n "$entry" ] && [ "${entry:0:1}" != "#" ]; then
                Safer_rmrf "$entry" "$1"
            fi
        done < .gitignore
    fi
}

function Set_deviceipconf {
    # DEVICEIPCONF defines ip settings for dom0 (for nfsroot these are needed during kernel boot already)
    case "$BUILDOPT" in
    dhcp)
        # dhcp configuration
        DEVICEIPCONF="::::${DEVICEHN}-dom0:eth0:dhcp"
    ;;
    static)
        # static IP configuration
        DEVICEIPCONF="${DEVICEIP}::${DEVICEGW}:${DEVICENM}:${DEVICEHN}-dom0:eth0:off:${DEVICEDNS}"
    ;;
    *)
        # IP configuration not used at boot time (SD/USB)
        DEVICEIPCONF="invalid"
    ;;
    esac

    export DEVICEIPCONF
}

function Check_param_exist {
    if [ -z "$1" ]; then
        echo "Parameter not defined"
        exit 1
    fi
}

function Check_1_param_exist {
    Check_param_exist "$1"
}

function Check_2_param_exist {
    Check_param_exist "$1"
    Check_param_exist "$2"
}

function Check_3_param_exist {
    Check_param_exist "$1"
    Check_param_exist "$2"
    Check_param_exist "$3"
}

function Check_4_param_exist {
    Check_param_exist "$1"
    Check_param_exist "$2"
    Check_param_exist "$3"
    Check_param_exist "$4"
}

function Check_5_param_exist {
    Check_param_exist "$1"
    Check_param_exist "$2"
    Check_param_exist "$3"
    Check_param_exist "$4"
    Check_param_exist "$5"
}

function Check_6_param_exist {
    Check_param_exist "$1"
    Check_param_exist "$2"
    Check_param_exist "$3"
    Check_param_exist "$4"
    Check_param_exist "$5"
    Check_param_exist "$6"
}

function Check_sha {
    echo "Check_sha"
    # $1 is sha
    # $2 is file
    Check_2_param_exist "$1" "$2"
    echo "${1} *${2}" | shasum -a 256 --check -s --strict
    ok="$?"
    echo "val: <$ok>"
    if [ "$ok" == "0" ]; then
        echo 1 > shaok
    fi
    echo "Check_sha done"
}

function Download {
    Check_3_param_exist "$1" "$2" "$3"

    Download_artifactory_binary "$1" "$2" "$3" 0
}

function Download_artifactory_binary {
    local download_url
    local destdir
    local filename
    local tmpoutput
    local extra_options
    local from_artifactory

    echo "Download_artifactory_binary"

    Check_3_param_exist "$1" "$2" "$3" # can be empty"$4"
    download_url="$1"
    destdir="$2"
    filename="$3"
    tmpoutput="${destdir}/${filename}"
    from_artifactory="${4}"

    if [ -n "${DOWNLOAD_CACHE_DIR}" ]; then
        tmpoutput="${DOWNLOAD_CACHE_DIR}/${filename}"
        mkdir -p "${DOWNLOAD_CACHE_DIR}"
    fi

    if [ ! -f "${DOWNLOAD_CACHE_DIR}/${filename}" ] || [ -z "${DOWNLOAD_CACHE_DIR}" ] ; then
        if [ "${from_artifactory}" != "0" ]; then
            extra_options="-H X-JFrog-Art-Api:${ARTIFACTORY_API_KEY:?}"
        fi
        curl ${extra_options} -L "${download_url}" -o "${tmpoutput}"
    fi

    if [ -n "${DOWNLOAD_CACHE_DIR}" ]; then
        cp "${DOWNLOAD_CACHE_DIR}/${filename}" "${destdir}/${filename}"
    fi

    echo "Download_artifactory_binary done"
}

function Decompress_xz {
    Check_1_param_exist "$1"

    xz -dk "$1"
}

function Decompress_image {
    Check_1_param_exist "$1"

    echo "$1"

    7z e "$1" || true
}

function Umount_chroot_devs {
    Check_1_param_exist "$1"

    local rootfs

    rootfs=$1

    sudo umount "${rootfs}/dev/pts" || true > /dev/null
    sudo umount "${rootfs}/dev" || true > /dev/null
    sudo umount "${rootfs}/proc" || true > /dev/null
    sudo umount "${rootfs}/sys" || true > /dev/null
    sudo umount "${rootfs}/tmp" || true > /dev/null
}

function Mount_chroot_devs {
    Check_1_param_exist "$1"

    local rootfs

    rootfs=$1

    sudo mkdir -p "${rootfs}"
    sudo mount -o bind /dev "${rootfs}/dev"
    sudo mount -o bind /dev/pts "${rootfs}/dev/pts"
    sudo mount -o bind /proc "${rootfs}/proc"
    sudo mount -o bind /sys "${rootfs}/sys"
    sudo mount -o bind /tmp "${rootfs}/tmp"
}


function Mount_image {
    echo "Mount image"
    Check_2_param_exist "$1" "$2"

    if [ -d "$2" ]; then
        echo "Mounting: $1 to $2 -folder. Already mounted."
        #return
    fi
    mkdir -p "$2"
    if [ ! -f "$1" ]; then
        exit 1
    fi
    sudo mount "$1" "$2" || true
}

function Umount_image {
    echo "Umount image"
    Check_1_param_exist "$1"

    if ! [ -d "$1" ]; then
        echo "Umounting. $1 folder is not mounted."
        return
    fi

    Umount_chroot_devs "$1"

    sudo umount "$1"
    rmdir "$1"
}

# Sanity_check function will return the clean path or exit with an error
# if second argument is given, path does not need to exist
# usage example: CLEANPATH="$(Sanity_check <path to check> [non_existing])"
#   on error an error message is printed to stderr and CLEANPATH is empty and return value is nonzero
#   on success CLEANPATH is the cleaned up path to <path to check> and return value is zero
function Sanity_check {
    local tpath

    set +e

    if [ -z "$2" ]; then
        tpath="$(realpath -e "$1" 2>/dev/null)"
    else
        tpath="$(realpath -m "$1" 2>/dev/null)"
    fi

    # Explicitly allowed paths
    case "$tpath" in
    /usr/src/*) # For docker environment this needs to be allowed
        echo "$tpath"
        exit 0
    ;;
    *)
        # Do nothing
    ;;
    esac

    # Denied paths
    case "$tpath" in
    /bin*|/boot*|/dev*|/etc*|/lib*|/opt*|/proc*|/run*|/sbin*|/snap*|/sys*|/usr*|/var*|/home)
        echo "Will not touch host special directories" >&2
        exit 6
        ;;
    /)
        echo "Will not touch host root directory" >&2
        exit 2
        ;;
    "$(pwd)")
        echo "Will not touch current directory" >&2
        exit 3
        ;;
    "")
        echo "Path does not exist" >&2
        exit 4
        ;;
    "$HOME")
        echo "Will not touch user home directory" >&2
        exit 5
        ;;
    *)  # Path allowed
        echo "$tpath"
        exit 0
        ;;
    esac
}

function Compile_kernel {
    local kernel_src
    local arch
    local cross_compile
    local compile_dir
    local defconfig
    local extra_configs

    echo "Compile_kernel"
    Check_5_param_exist "$1" "$2" "$3" "$4" "$5" # $6 can be empty

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    defconfig="$5"
    extra_configs="$6"

    pushd "$kernel_src"
    # RUN in docker
    make O="${compile_dir}" ARCH="${arch}" CROSS_COMPILE="$cross_compile" "$defconfig"
    if [ -n "${extra_configs}" ]; then
        echo "Adding extra kernel configs:"
        echo "${extra_configs}"
        echo "${extra_configs}" >> "${compile_dir}/.config"
    fi
    # make O="$compile_dir" ARCH="$arch" CROSS_COMPILE="$cross_compile" menuconfig
    case "$arch" in
    x86_64)
        make O="$compile_dir" -j "$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" \
            bzImage modules > "${compile_dir}"/kernel_compile.log
    ;;
    *)
        make O="$compile_dir" -j "$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" \
            Image modules dtbs > "${compile_dir}"/kernel_compile.log
    ;;
    esac
    popd
    # RUN in docker end

    echo "Compile_kernel done"
}

function Install_kernel {
    local arch
    local compile_dir
    local kernel_install_dir

    echo "Install_kernel"
    Check_3_param_exist "$1" "$2" "$3"

    arch="$1"
    compile_dir="$2"
    kernel_install_dir="$3"

    if [ "$arch" == "arm64" ]; then
        cp "${compile_dir}/arch/arm64/boot/Image" "$kernel_install_dir"
    else
        echo "Arch: $arch is not supported" >&2
        exit 1
    fi
    echo "Install_kernel done"
}

function Install_kernel_modules {
    local kernel_src
    local arch
    local cross_compile
    local compile_dir
    local rootfs
    local mntrootfs

    echo "Install_kernel_modules"
    Check_5_param_exist "$1" "$2" "$3" "$4" "$5"

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    rootfs="$5"

    mntrootfs="$(Sanity_check "$rootfs")"

    pushd "$kernel_src"
    # RUN in docker
    # Don't complain about sudo redirect, it's okay here
    # shellcheck disable=SC2024
    sudo make "O=${compile_dir}" "ARCH=${arch}" "CROSS_COMPILE=${cross_compile}" "INSTALL_MOD_PATH=${mntrootfs}" \
        modules_install > "${compile_dir}/modules_install.log"
    # RUN in docker end
    popd

    # Create module deps files
    echo "Create module dep files"
    KVERSION="$(cut -d "\"" -f 2 "${compile_dir}/include/generated/utsrelease.h")"
    echo "Compiled kernel version: ${KVERSION}"
    sudo chroot "$mntrootfs" depmod -a "${KVERSION}"

    echo "Install_kernel_modules done"
}

function Compile_xen {
    local src
    local version

    echo "Compile_xen"
    Check_2_param_exist "$1" "$2"

    src="$1"
    version="$2"

    # Build xen
    if [ ! -s "${src}/xen/xen" ]; then
        pushd "${src}"
        git checkout "${version}"

        if [ ! -s xen/.config ]; then
            #echo "CONFIG_DEBUG=y" > xen/arch/arm/configs/arm64_defconfig
            #echo "CONFIG_SCHED_ARINC653=y" >> xen/arch/arm/configs/arm64_defconfig
            make -C xen XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
        fi
        make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dist-xen -j "$(nproc)"
        popd
    fi

    echo "Compile_xen done"
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
