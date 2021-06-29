#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh

# Set exit on error, so shellcheck won't suggest '|| exit 1' everywhere
set -e

# Get actual directory of this bash script
HDIR="$(dirname "${BASH_SOURCE[0]}")"
HDIR="$(realpath "$HDIR")"

# Minimum config for config generation
function Min_config {
    local flags

    # Save flags
    flags="$-"

    # Enable automatic export of global environment variables
    # So config settings are all exported (for e.g. Makefile use)
    set -a

    # Set main source directory for other scripts
    TCDIST_DIR="${HDIR}"

    # Set output dir only if not specified in environment already
    if [ -z "$TCDIST_OUTPUT" ]; then
        if [ -f "${TCDIST_DIR}/.tcdist_output" ]; then
            # Let .tcdist_output file set TCDIST_OUTPUT
            # shellcheck disable=SC1091,SC1090
            . "${TCDIST_DIR}/.tcdist_output"
            if [ -z "$TCDIST_OUTPUT" ]; then
                echo "${TCDIST_DIR}/.tcdist_output was sourced, but it did not set TCDIST_OUTPUT" >&2
                exit 1
            fi
        else
            # Use main source dir
            TCDIST_OUTPUT="$TCDIST_DIR"
        fi
    fi

    # Restore a flag
    if [[ "$flags" =~ "a" ]]; then
        set -a
    else
        set +a
    fi
}

# Loads build system configurations
# Disable complaints about arguments they are optional here
# shellcheck disable=SC2120
function Load_config {
    local flags

    Min_config

    # Save flags
    flags="$-"

    # Enable automatic export of global environment variables
    # So config settings are all exported (for e.g. Makefile use)
    set -a

    # Load defaults in case .setup_sh_config is missing any settings
    # for example .setup_sh_config could be from older revision
    # disable shellchecking of default_setup_sh_config and warnings about it
    # shellcheck disable=SC1091,SC1090
    . "${TCDIST_DIR}/default_setup_sh_config"

    if [ -f "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT}" ]; then
        # disable shellchecking of .setup_sh_config${TCDIST_PRODUCT} and warnings about it
        # shellcheck disable=SC1091,SC1090
        . "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT}"
    else
        if [ -n "${TCDIST_PRODUCT}" ]; then
            echo "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT} doesn't exist"
            exit 1
        fi
    fi

    TCDIST_SETUP_SH_CONFIG=".setup_sh_config${TCDIST_PRODUCT}"

    # Convert some options to lower case
    TCDIST_ARCH="${TCDIST_ARCH,,}"
    TCDIST_PLATFORM="${TCDIST_PLATFORM,,}"
    TCDIST_HYPERVISOR="${TCDIST_HYPERVISOR,,}"
    TCDIST_BUILDOPT="${TCDIST_BUILDOPT,,}"
    TCDIST_SUDOTYPE="${TCDIST_SUDOTYPE,,}"

    # Restore a flag
    if [[ "$flags" =~ "a" ]]; then
        set -a
    else
        set +a
    fi

    if [ "$1" != "nocheck" ]; then
        case "$TCDIST_ARCH" in
        x86)
            case "$TCDIST_SUB_ARCH" in
            intel|amd)
                # Options ok
            ;;
            *)
                echo "Invalid TCDIST_SUB_ARCH: $TCDIST_SUB_ARCH" >&2
                exit 1
            ;;
            esac
        ;;
        arm64)
            if [ -n "$TCDIST_SUB_ARCH" ] ; then
                echo "Invalid TCDIST_SUB_ARCH for $TCDIST_PLATFORM, please leave blank." >&2
                exit 1
            fi
        ;;
        *)
            echo "Invalid TCDIST_ARCH: $TCDIST_ARCH" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_PLATFORM" in
        raspi4)
            # Options ok
        ;;
        ls1012afrwy)
            # Options ok
        ;;
        qemu)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_PLATFORM: $TCDIST_PLATFORM" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_HYPERVISOR" in
        xen|kvm)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_HYPERVISOR: $TCDIST_HYPERVISOR" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_BUILDOPT" in
        usb|mmc|dhcp|static)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_BUILDOPT: $TCDIST_BUILDOPT" >&2
            exit 1
        esac

        case "$TCDIST_SUDOTYPE" in
        standard)
            # Disable sudo function if standard sudo is requested
            unset sudo
        ;;
        showonpassword|verbose|confirm)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_SUDOTYPE: $TCDIST_SUDOTYPE" >&2
            exit 1
        ;;
        esac
    fi

    Set_deviceipconf
}

# Get path to sudo binary (or empty if not available, but don't fail here)
SUDOCMD="$(command -v sudo || true)"

# sudo function will show the command about to be run if password is prompted for
# if TCDIST_SUDOTYPE=verbose then all commands will be shown
# if TCDIST_SUDOTYPE=confirm then all commands will be confirmed regardless of password prompting
# if left in the confirm prompt for a long time, then sudo might ask password again after confirmation, but it is what it is
# sudo function meant to replace sudo command, so it is not capitalized like other functions
function sudo {
    local prompt
    local inp

    prompt="$(printf "About to sudo: \"%s\"" "$*")"

    # Check if sudo is going to ask password or not
    if "${SUDOCMD:?}" -n true 2> /dev/null; then
        case "$TCDIST_SUDOTYPE" in
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
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} with xen configuration" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    cp -f default_setup_sh_config "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Kvmconfig {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} with kvm configuration" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    # Change TCDIST_HYPERVISOR option to kvm
    sed "s/^TCDIST_HYPERVISOR=.*/TCDIST_HYPERVISOR=kvm/" < default_setup_sh_config > "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function X86config {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for x86 qemu" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    # Change several options for x86 build
    sed -e "s/^TCDIST_HYPERVISOR=.*/TCDIST_HYPERVISOR=kvm/" \
        -e "s/^TCDIST_ARCH=.*/TCDIST_ARCH=x86/" \
        -e "s/^TCDIST_PLATFORM=.*/TCDIST_PLATFORM=qemu/" \
        -e "s/^TCDIST_SUB_ARCH=.*/TCDIST_SUB_ARCH=intel/" \
        -e "s/^TCDIST_BUILDOPT=.*/TCDIST_BUILDOPT=dhcp/" \
        -e "s/^TCDIST_KERNEL_IMAGE_FILE=.*/TCDIST_KERNEL_IMAGE_FILE=bzImage/" \
        -e "s/^TCDIST_LINUX_BRANCH=.*/TCDIST_LINUX_BRANCH=tc-x86-5.10-dev/" \
        -e "s/^TCDIST_DEVICEHN=.*/TCDIST_DEVICEHN=x86/" < default_setup_sh_config > "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    sed -e "s/^TCDIST_HYPERVISOR=.*/TCDIST_HYPERVISOR=kvm/" \
        -e "s/^TCDIST_ARCH=.*/TCDIST_ARCH=arm64/" \
        -e "s/^TCDIST_BUILDOPT=.*/TCDIST_BUILDOPT=mmc/" \
        -e "s/^TCDIST_LINUX_BRANCH=.*/TCDIST_LINUX_BRANCH=xen/" < default_setup_sh_config > "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config_ls1012a {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64 ls1012afrwy" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    sed -e "s/^TCDIST_HYPERVISOR=.*/TCDIST_HYPERVISOR=kvm/" \
        -e "s/^TCDIST_ARCH=.*/TCDIST_ARCH=arm64/" \
        -e "s/^TCDIST_PLATFORM=.*/TCDIST_PLATFORM=ls1012afrwy/" \
        -e "s/^TCDIST_BUILDOPT=.*/TCDIST_BUILDOPT=mmc/" \
        -e "s/^TCDIST_DEVTREE=.*/TCDIST_DEVTREE=fsl-ls1012a-frwy.dtb/" \
        -e "s/^TCDIST_LINUX_BRANCH=.*/TCDIST_LINUX_BRANCH=tc-nxp-5.4-dev/" < default_setup_sh_config > "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
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
    # TCDIST_DEVICEIPCONF defines ip settings for dom0 (for nfsroot these are needed during kernel boot already)
    case "$TCDIST_BUILDOPT" in
    dhcp)
        # dhcp configuration
        TCDIST_DEVICEIPCONF="::::${TCDIST_DEVICEHN}-dom0:eth0:dhcp"
    ;;
    static)
        # static IP configuration
        TCDIST_DEVICEIPCONF="${TCDIST_DEVICEIP}::${TCDIST_DEVICEGW}:${TCDIST_DEVICENM}:${TCDIST_DEVICEHN}-dom0:eth0:off:${TCDIST_DEVICEDNS}"
    ;;
    *)
        # IP configuration not used at boot time (SD/USB)
        TCDIST_DEVICEIPCONF="invalid"
    ;;
    esac

    export TCDIST_DEVICEIPCONF
}

# Check proper number of parameters given
# First parameter is the number of parameters expected the rest are the parameters
# Negative number of parameters turns off empty parameter checking
function Check_params {
    local checkempty=1
    local i=0
    local expected
    local param

    expected="${1:?}"

    shift

    if [ "$expected" -lt 0 ]; then
        # check only the number of parameters, empty parameters allowed
        expected=$((-expected))
        checkempty=0
    fi

    if [ "$#" -lt "$expected" ]; then
        echo "${FUNCNAME[1]}: Invalid number of parameters (expected $expected got $#)" >&2
        exit 1
    fi

    if [ "$checkempty" == 1 ]; then
        for param in "$@"; do
            if [ "$i" -eq "$expected" ]; then
                # Only check up to expected number of parameters, extra parameters may be empty
                break
            fi
            if [ -z "$param" ]; then
                echo "${FUNCNAME[1]}: Empty parameters not allowed" >&2
                exit 1
            fi
            i=$((i + 1))
        done
    fi
}

function Check_sha {
    echo "Check_sha"
    # $1 is sha
    # $2 is file
    Check_params 2 "$@"
    echo "${1} *${2}" | shasum -a 256 --check -s --strict
    ok="$?"
    echo "val: <$ok>"
    if [ "$ok" == "0" ]; then
        echo 1 > shaok
    fi
    echo "Check_sha done"
}

function Download {
    Check_params 3 "$@"

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

    Check_params 3 "$@"
    download_url="$1"
    destdir="$2"
    filename="$3"
    tmpoutput="${destdir}/${filename}"
    from_artifactory="${4}"

    if [ -n "${TCDIST_DL_CACHE_DIR}" ]; then
        tmpoutput="${TCDIST_DL_CACHE_DIR}/${filename}"
        mkdir -p "${TCDIST_DL_CACHE_DIR}"
    fi

    if [ ! -f "${TCDIST_DL_CACHE_DIR}/${filename}" ] || [ -z "${TCDIST_DL_CACHE_DIR}" ] ; then
        if [ "${from_artifactory}" != "0" ]; then
            extra_options="-k -H X-JFrog-Art-Api:${TCDIST_ARTIFACTORY_API_KEY:?}"
        fi
        # extra_options contains options separated with spaces, so it is purposefully unquoted
        # shellcheck disable=SC2086
        curl ${extra_options} -L "${download_url}" -o "${tmpoutput}"
    fi

    if [ -n "${TCDIST_DL_CACHE_DIR}" ]; then
        cp "${TCDIST_DL_CACHE_DIR}/${filename}" "${destdir}/${filename}"
    fi

    echo "Download_artifactory_binary done"
}

function Decompress_xz {
    Check_params 1 "$@"

    xz -dk "$1"
}

function Decompress_image {
    Check_params 1 "$@"

    echo "$1"

    7z e "$1" || true
}

function Umount_chroot_devs {
    Check_params 1 "$@"

    local rootfs

    rootfs=$1

    sudo umount "${rootfs}/dev/pts" || true > /dev/null
    sudo umount "${rootfs}/dev" || true > /dev/null
    sudo umount "${rootfs}/proc" || true > /dev/null
    sudo umount "${rootfs}/sys" || true > /dev/null
    sudo umount "${rootfs}/tmp" || true > /dev/null
}

function Mount_chroot_devs {
    Check_params 1 "$@"

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
    Check_params 2 "$@"

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
    Check_params 1 "$@"

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
    local build_targets
    local kernel_branch

    echo "Compile_kernel"
    Check_params 5 "$@"

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    defconfig="$5"
    extra_configs="$6"
    kernel_branch="$7"

    case "$arch" in
    x86_64)
        build_targets="bzImage"
    ;;
    *)
        build_targets="Image dtbs"
    ;;
    esac

    # Secure-os disables modules, so only try to build them with !secure-os
    if [ "$TCDIST_SECUREOS" = "0" ] ; then
        build_targets+=" modules"
    fi

    pushd "$kernel_src"
    if [ "$kernel_branch" != "" ] ; then
        git checkout "$kernel_branch"
    else
        # Default branch for now is 'xen', to be fixed later
        git checkout xen
    fi
    # RUN in docker
    make O="${compile_dir}" ARCH="${arch}" CROSS_COMPILE="$cross_compile" "$defconfig"
    if [ -n "${extra_configs}" ]; then
        echo "Adding extra kernel configs:"
        echo "${extra_configs}"
        echo "${extra_configs}" >> "${compile_dir}/.config"
    fi
    # make O="$compile_dir" ARCH="$arch" CROSS_COMPILE="$cross_compile" menuconfig
    # shellcheck disable=SC2086
    make O="$compile_dir" -j "$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" \
            ${build_targets} > "${compile_dir}"/kernel_compile.log

    popd
    # RUN in docker end

    echo "Compile_kernel done"
}

function Install_kernel {
    local arch
    local compile_dir
    local kernel_install_dir

    echo "Install_kernel"
    Check_params 3 "$@"

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
    local sudocommand

    echo "Install_kernel_modules"
    Check_params 5 "$@"

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    rootfs="$5"

    mntrootfs="$(Sanity_check "$rootfs")"

    # If sixth parameter was given, use it as sudo command (if explicitly empty string, sudo is not used)
    if [ $# -eq 6 ]; then
        sudocommand="$6"
    else
        sudocommand="sudo"
    fi

    pushd "$kernel_src"
    # RUN in docker
    ${sudocommand} make "O=${compile_dir}" "ARCH=${arch}" "CROSS_COMPILE=${cross_compile}" "INSTALL_MOD_PATH=${mntrootfs}" \
        modules_install > "${compile_dir}/modules_install.log"
    # RUN in docker end
    popd

    # Create module deps files
    echo "Create module dep files"
    KVERSION="$(cut -d "\"" -f 2 "${compile_dir}/include/generated/utsrelease.h")"
    echo "Compiled kernel version: ${KVERSION}"
    ${sudocommand} depmod -b "${mntrootfs}" -a "${KVERSION}"

    echo "Install_kernel_modules done"
}

function Compile_xen {
    local src
    local version

    echo "Compile_xen"
    Check_params 2 "$@"

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
    mkdir -p "$TCDIST_BOOTMNT"
    mkdir -p "$TCDIST_ROOTMNT"
    mkdir -p "${TCDIST_ROOTMNT}-su"
    mkdir -p "$TCDIST_DOMUMNT"
    mkdir -p "${TCDIST_DOMUMNT}-su"
}

function Bind_mounts {
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${TCDIST_ROOTMNT}-su" "$TCDIST_ROOTMNT"
    sudo bindfs "--map=0/${MYUID}:@0/@$MYGID" "${TCDIST_DOMUMNT}-su" "$TCDIST_DOMUMNT"
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
        if [ "$TCDIST_AUTOMOUNT" == "1" ]; then
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

    sudo mount -o "uid=${MYUID},gid=$MYGID" "$PART1" "$TCDIST_BOOTMNT"
    sudo mount "$PART2" "${TCDIST_ROOTMNT}-su"
    sudo mount "$PART3" "${TCDIST_DOMUMNT}-su"
    Bind_mounts
}

function Mount {
    local dev
    local midp

    set +e

    if [ -z "$1" ]; then
        dev="$TCDIST_DEFDEV"
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

        sudo mount -o "uid=${MYUID},gid=$MYGID" "${dev}${midp}1" "$TCDIST_BOOTMNT"
        sudo mount "${dev}${midp}2" "${TCDIST_ROOTMNT}-su"
        sudo mount "${dev}${midp}3" "${TCDIST_DOMUMNT}-su"
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
        sudo umount "$TCDIST_BOOTMNT"
        sudo umount "$TCDIST_ROOTMNT"
        sudo umount "$TCDIST_DOMUMNT"
        sudo umount "${TCDIST_ROOTMNT}-su"
        sudo umount "${TCDIST_DOMUMNT}-su"
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

    mounted="$(mount | grep "$TCDIST_BOOTMNT")"
    if [ -z "$mounted" ]; then
        return 0
    fi

    if [ "$1" == "mark" ]; then
        echo 'THIS_IS_BOOTFS' > "${TCDIST_BOOTMNT}/THIS_IS_BOOTFS"
        echo 'THIS_IS_ROOTFS' > "${TCDIST_ROOTMNT}/THIS_IS_ROOTFS"
        echo 'THIS_IS_DOMUFS' > "${TCDIST_DOMUMNT}/THIS_IS_DOMUFS"
    fi
    sudo umount "$TCDIST_BOOTMNT"
    sudo umount "$TCDIST_ROOTMNT"
    sudo umount "$TCDIST_DOMUMNT"
    sudo umount "${TCDIST_ROOTMNT}-su"
    sudo umount "${TCDIST_DOMUMNT}-su"
    sync
}

# Checks if we are running in docker or not from script dir
function In_docker {
    if [ "$HDIR" == "/usr/src" ]; then
        return 0;
    fi
    return 1
}

# Checks scripts with shellcheck and bashate
function Shellcheck_bashate {
    local sc
    local bh
    set +e

    shellcheck "$@"
    sc=$?
    # Ignore "E006 Line too long" errors
    bashate -i E006 "$@"
    bh=$?

    if [ "$sc" -eq 0 ] && [ "$bh" -eq 0 ]; then
        echo "Nothing to complain" >&2
    else
        echo "Problems found" >&2
    fi

    return $((sc+bh))
}

# Fetches all branches from remote repo and makes them track remote branches
function Fetch_all {
    local dir
    local outp
    local remote

    dir="$1"

    # If directory not given, use original current directory
    if [ -z "$dir" ]; then
        dir="$OPWD"
        if [ -z "$dir" ]; then
            # If OPWD is not set, something is wrong
            echo "OPWD is not set, did you run fetch_all via setup.sh?" >&2
            return 1
        fi
    fi

    pushd "$dir" > /dev/null

    outp="$(git branch -r | grep -v '\->')"
    while read -r remote; do
        # Try to create matching branch
        if ! git branch --track "${remote#origin/}" "$remote" 2> /dev/null; then
            # If failed, assume branch exists, so make sure it tracks branch from origin
            git branch --set-upstream-to="$remote" "${remote#origin/}"
        fi
    done <<< "$outp"

    # Fetch all branches
    git fetch --all

    popd > /dev/null
}

# Just run make (with currently loaded configuration)
function Make {

    # If running make on main level, (re)generate Makefile
    if [ "$OPWD" == "$TCDIST_DIR" ]; then
        Makefile > "${TCDIST_OUTPUT:?}/Makefile.def"
    fi

    make -C "$OPWD" "$@"
}

# Amake runs make for all selected vms with given parameters
function Amake {
    local vm

    for vm in "${TCDIST_VMLIST[@]}"; do
        make -C "$vm" "$@"
    done
}

# Finds first argument in the following list of arguments
# Can be used e.g. to get index of an element in an array
function Index_of {
    local i=0
    local j
    local elm

    elm="$1"
    shift

    for j in "$@"; do
        if [ "$elm" == "$j" ]; then
            echo "$i"
            return 0
        fi
        i=$((i+1))
    done
}

# Escapes given parameters to a string
function Escape {
    local a

    printf "%q" "$1"
    shift

    for a in "$@"; do
        printf " %q" "$a"
    done

    printf "\n"
}

# Runs a command in bash or opens a shell (With configuration loaded in environment)
function Bash {
    cd "$OPWD"
    if [ $# -gt 0 ]; then
        bash -c "$(Escape "$@")"
    else
        bash --init-file <(echo ". \"$HOME/.bashrc\";echo TCDIST shell")
    fi
}
