#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh

# Get actual directory of this bash script
HDIR="$(dirname "${BASH_SOURCE[0]}")"
HDIR="$(realpath "$HDIR")"

# Loads build system configurations
function Load_config {
    # Load defaults in case .setup_sh_config is missing any settings
    # for example .setup_sh_config could be from older revision
    . "${HDIR}/default_setup_sh_config"

    if [ -f "${HDIR}/.setup_sh_config" ]; then
        . "${HDIR}/.setup_sh_config"
    fi

    Set_deviceipconf

    # Disable sudo function if standard sudo is requested
    if [ "$STDSUDO" == "1" ]; then
        unset sudo
    fi
}

# This translation here only to facilitate smooth transition with docker repo
# Can be removed after docker repo has been updated
function load_config {
    Load_config
}

# Get path to sudo binary (or empty if not available, but don't fail here)
SUDOCMD="$(command -v sudo || true)"

# Verbose sudo, will show the command about to be run if password is prompted for
# At least for the very first run you'll know what is about to happen as root
# If SUDOCHECK=1 then all commands will be confirmed
# sudo function meant to replace sudo command, so it is not capitalized like other functions
function sudo {
    local PROMPT
    local INP

    PROMPT="$(printf "About to sudo: \"%s\"" "$*")"

    # Check if sudo is going to ask password or not
    if "${SUDOCMD:?}" -n true 2> /dev/null; then
        # Ask for confirmation if SUDOCHECK enabled
        if [ "$SUDOCHECK" == "1" ]; then
            INP="x"
            while [ "$INP" == "x" ]; do
                printf "%s\nConfirm (Y/n): " "$PROMPT" > /dev/tty
                read -r INP < /dev/tty
                case "$INP" in
                ""|y|Y)
                    INP="Y"
                ;;
                n|N)
                    return 1
                ;;
                *)
                    echo "Invalid input" > /dev/tty
                    INP="x"
                ;;
                esac
            done
        fi

        "${SUDOCMD:?}" "$@"
    else
        # If sudo is going to ask password show the command about to be run anyway
        printf "%s\n" "$PROMPT" > /dev/tty
        "${SUDOCMD:?}" "$@"
    fi
}

function Defconfig {
    echo "Creating .setup_sh_config with defaults" >&2
    cp -f default_setup_sh_config .setup_sh_config
}

function Kvmconfig {
    echo "Creating .setup_sh_config with kvm configuration" >&2
    sed "s/HYPERVISOR=.*/HYPERVISOR=KVM/" < default_setup_sh_config > .setup_sh_config
}

function X86config {
    echo "Creating .setup_sh_config for x86" >&2
    sed -e "s/HYPERVISOR=.*/HYPERVISOR=KVM/" \
        -e "s/PLATFORM=.*/PLATFORM=x86/" \
        -e "s/BUILDOPT=.*/BUILDOPT=2/" \
        -e "s/KERNEL_IMAGE=.*/KERNEL_IMAGE=\$IMAGES\/bzImage/" \
        -e "s/DEVICEHN=.*/DEVICEHN=x86/" < default_setup_sh_config > .setup_sh_config
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
    local LCH

    LCH="${1: -1}"
    case "$LCH" in
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
    esac
}

# Trims off whitespace from start and end of a string
function Trim {
    local STR

    STR="$*"

    # remove whitespace from start
    STR="${STR#"${STR%%[![:space:]]*}"}"

    # remove whitespace from end
    STR="${STR%"${STR##*[![:space:]]}"}"

    printf '%s' "$STR"
}

# Slightly safer recursive deletion
# If second parameter is 'sudo' root user is used to remove files
function Safer_rmrf {
    local RMD

    # Sanity check the path, just in case
    RMD="$(Sanity_check "$1" ne)"
    if [  "$2" == "sudo" ]; then
        # Check that we actually have something to delete before using sudo
        if [ -e "${RMD:?}" ]; then
            sudo rm -rf "${RMD:?}"
        fi
    else
        rm -rf "${RMD:?}"
    fi
}

# Remove files and directories listed in .gitignores
function Remove_ignores {
    local ENTRY

    if [ -f .gitignore ]; then
        while IFS= read -r ENTRY; do
            ENTRY="$(Trim "$ENTRY")"
            if [ -n "$ENTRY" ] && [ "${ENTRY:0:1}" != "#" ]; then
                Safer_rmrf "$ENTRY" "$1"
            fi
        done < .gitignore
    fi
}

function Set_deviceipconf {
    # DEVICEIPCONF defines ip settings for dom0 (for nfsroot these are needed during kernel boot already)
    case "$BUILDOPT" in
    2)
        # dhcp configuration
        DEVICEIPCONF="::::${DEVICEHN}-dom0:eth0:dhcp"
    ;;
    3)
        # static IP configuration
        DEVICEIPCONF="${DEVICEIP}::${DEVICEGW}:${DEVICENM}:${DEVICEHN}-dom0:eth0:off:${DEVICEDNS}"
    ;;
    *)
        # IP configuration not used at boot time (SD/USB)
        DEVICEIPCONF="invalid"
    ;;
    esac
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
    echo "Download_artifactory_binary"
    local DOWNLOAD_PATH
    local DESTDIR
    local TMPOUTPUT
    local EXTRA_OPTIONS
    local FROM_ARTIFACTORY

    Check_3_param_exist "$1" "$2" "$3" # can be empty"$4"
    DOWNLOAD_URL="$1"
    DESTDIR="$2"
    FILENAME="$3"
    TMPOUTPUT="${DESTDIR}/${FILENAME}"
    FROM_ARTIFACTORY="${4}"

    if [ -n "${DOWNLOAD_CACHE_DIR}" ]; then
        TMPOUTPUT="${DOWNLOAD_CACHE_DIR}/${FILENAME}"
        mkdir -p ${DOWNLOAD_CACHE_DIR}
    fi

    if [ ! -f "${DOWNLOAD_CACHE_DIR}/${FILENAME}" ] || [ ! -n "${DOWNLOAD_CACHE_DIR}" ] ; then
        if [ "${FROM_ARTIFACTORY}" != "0" ]; then
            EXTRA_OPTIONS="-H X-JFrog-Art-Api:${ARTIFACTORY_API_KEY:?}"
        fi
        curl ${EXTRA_OPTIONS} -L "${DOWNLOAD_URL}" -o "${TMPOUTPUT}"
    fi

    if [ -n "${DOWNLOAD_CACHE_DIR}" ]; then
        cp "${DOWNLOAD_CACHE_DIR}/${FILENAME}" "${DESTDIR}/${FILENAME}"
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

    local ROOTFS

    ROOTFS=$1

    sudo umount "${ROOTFS}/dev/pts" || true > /dev/null
    sudo umount "${ROOTFS}/dev" || true > /dev/null
    sudo umount "${ROOTFS}/proc" || true > /dev/null
    sudo umount "${ROOTFS}/sys" || true > /dev/null
    sudo umount "${ROOTFS}/tmp" || true > /dev/null
}

function Mount_chroot_devs {
    Check_1_param_exist "$1"

    local ROOTFS

    ROOTFS=$1

    sudo mkdir -p "${ROOTFS}"
    sudo mount -o bind /dev "${ROOTFS}/dev"
    sudo mount -o bind /dev/pts "${ROOTFS}/dev/pts"
    sudo mount -o bind /proc "${ROOTFS}/proc"
    sudo mount -o bind /sys "${ROOTFS}/sys"
    sudo mount -o bind /tmp "${ROOTFS}/tmp"
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
    local TPATH

    set +e

    if [ -z "$2" ]; then
        TPATH="$(realpath -e "$1" 2>/dev/null)"
    else
        TPATH="$(realpath -m "$1" 2>/dev/null)"
    fi

    # Explicitly allowed paths
    case "$TPATH" in
    /usr/src/*) # For docker environment this needs to be allowed
        echo "$TPATH"
        exit 0
    ;;
    *)
        # Do nothing
    ;;
    esac

    # Denied paths
    case "$TPATH" in
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
        echo "$TPATH"
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

    pushd $kernel_src
    # RUN in docker
    make O="${compile_dir}" ARCH="${arch}" CROSS_COMPILE="$cross_compile" "$defconfig"
    if [ -n "${extra_configs}" ]; then
        echo "Adding extra kernel configs:"
        echo "${extra_configs}"
        echo "${extra_configs}" >> "${compile_dir}/.config"
    fi
    # make O="$compile_dir" ARCH="$arch" CROSS_COMPILE="$cross_compile" menuconfig
    make O="$compile_dir" -j "$(nproc)" ARCH="$arch" CROSS_COMPILE="$cross_compile" Image modules dtbs \
        > "${compile_dir}"/kernel_compile.log
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
    local KERNEL_SRC
    local ARCH
    local CROSS_COMPILE
    local COMPILE_DIR
    local ROOTFS
    local MNTROOTFS

    echo "Install_kernel_modules"
    Check_5_param_exist "$1" "$2" "$3" "$4" "$5"

    KERNEL_SRC="$1"
    ARCH="$2"
    CROSS_COMPILE="${CCACHE} $3"
    COMPILE_DIR="$4"
    ROOTFS="$5"

    MNTROOTFS="$(Sanity_check "$ROOTFS")"

    pushd "$KERNEL_SRC" || exit 255
    # RUN in docker
    sudo make "O=${COMPILE_DIR}" "ARCH=${ARCH}" "CROSS_COMPILE=${CROSS_COMPILE}" "INSTALL_MOD_PATH=${MNTROOTFS}" \
        modules_install > "${COMPILE_DIR}/modules_install.log"
    # RUN in docker end
    popd || exit 255

    # Create module deps files
    echo "Create module dep files"
    KVERSION="$(cut -d "\"" -f 2 "${COMPILE_DIR}/include/generated/utsrelease.h")"
    echo "Compiled kernel version: ${KVERSION}"
    sudo chroot "$MNTROOTFS" depmod -a "${KVERSION}"

    echo "Install_kernel_modules done"
}

function Compile_xen {
    echo "Compile_xen"
    Check_2_param_exist "$1" "$2"

    local SRC
    local VERSION

    SRC="$1"
    VERSION="$2"

    # Build xen
    if [ ! -s "${SRC}/xen/xen" ]; then
        pushd "${SRC}" || exit 255
        git checkout "${VERSION}"

        if [ ! -s xen/.config ]; then
            #echo "CONFIG_DEBUG=y" > xen/arch/arm/configs/arm64_defconfig
            #echo "CONFIG_SCHED_ARINC653=y" >> xen/arch/arm/configs/arm64_defconfig
            make -C xen XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
        fi
        make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dist-xen -j "$(nproc)"
        popd || exit 255
    fi

    echo "Compile_xen done"
}
