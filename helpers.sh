#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh
# compile <args>

function defconfig {
    echo "Creating .setup_sh_config with defaults" >&2
    cp -f default_setup_sh_config .setup_sh_config
}

function kvmconfig {
    echo "Creating .setup_sh_config with kvm configuration" >&2
    sed "s/HYPERVISOR=.*/HYPERVISOR=KVM/" < default_setup_sh_config > .setup_sh_config
}

function x86config {
    echo "Creating .setup_sh_config for x86" >&2
    sed -e "s/HYPERVISOR=.*/HYPERVISOR=KVM/" \
        -e "s/PLATFORM=.*/PLATFORM=x86/" \
        -e "s/BUILDOPT=.*/BUILDOPT=2/" \
        -e "s/KERNEL_IMAGE=.*/KERNEL_IMAGE=\$IMAGES\/bzImage/" \
        -e "s/RASPHN=.*/RASPHN=x86/" < default_setup_sh_config > .setup_sh_config
}

# Returns 0 if function exists, 1 if not
function fn_exists {
    if [ "$(LC_ALL=C type -t "$1")" == "function" ]; then
        return 0
    else
        echo "$1: Unknown function" >&2
        return 1
    fi
}

# Calculates actual number of bytes from strings like '4G' and '23M' plain numbers are sectors (512 bytes)
function actual_value {
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
function trim {
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
function safer_rmrf {
    local RMD

    # Sanity check the path, just in case
    RMD="$(sanitycheck "$1" ne)"
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
function remove_ignores {
    local ENTRY

    if [ -f .gitignore ]; then
        while IFS= read -r ENTRY; do
            ENTRY="$(trim "$ENTRY")"
            if [ -n "$ENTRY" ] && [ "${ENTRY:0:1}" != "#" ]; then
                safer_rmrf "$ENTRY" "$1"
            fi
        done < .gitignore
    fi
}

function set_ipconfraspi {
    # IPCONFRASPI defines ip settings for dom0 (for nfsroot these are needed during kernel boot already)
    case "$BUILDOPT" in
    2)
        # dhcp configuration
        IPCONFRASPI="::::${RASPHN}-dom0:eth0:dhcp"
    ;;
    3)
        # static IP configuration
        IPCONFRASPI="${RASPIP}::${RASPGW}:${RASPNM}:${RASPHN}-dom0:eth0:off:${RASPDNS}"
    ;;
    *)
        # IP configuration not used at boot time (SD/USB)
        IPCONFRASPI="invalid"
    ;;
    esac
}

function check_param_exist {
    if [ -z "$1" ]; then
        echo "Parameter not defined"
        exit 1
    fi
}

function check_1_param_exist {
    check_param_exist "$1"
}

function check_2_param_exist {
    check_param_exist "$1"
    check_param_exist "$2"
}

function check_3_param_exist {
    check_param_exist "$1"
    check_param_exist "$2"
    check_param_exist "$3"
}

function check_4_param_exist {
    check_param_exist "$1"
    check_param_exist "$2"
    check_param_exist "$3"
    check_param_exist "$4"
}

function check_5_param_exist {
    check_param_exist "$1"
    check_param_exist "$2"
    check_param_exist "$3"
    check_param_exist "$4"
    check_param_exist "$5"
}

function check_6_param_exist {
    check_param_exist "$1"
    check_param_exist "$2"
    check_param_exist "$3"
    check_param_exist "$4"
    check_param_exist "$5"
    check_param_exist "$6"
}

function check_sha {
    # $1 is sha
    # $2 is file
    check_2_param_exist "$1" "$2"
    echo "${1} *${2}" | shasum -a 256 --check -s --strict
    ok="$?"
    echo "val: <$ok>"
    if [ "$ok" == "0" ]; then
        echo 1 > shaok
    fi
}

function download {
    check_1_param_exist "$1"
    wget "$1"
}

function decompress_xz {
    check_1_param_exist "$1"

    xz -dk "$1"
}

function decompress_image {
    check_1_param_exist "$1"

    echo "$1"

    7z e "$1" || true
}

umount_chroot_devs () {
    check_1_param_exist "$1"

    local ROOTFS

    ROOTFS=$1

    sudo umount "${ROOTFS}/dev/pts" || true > /dev/null
    sudo umount "${ROOTFS}/dev" || true > /dev/null
    sudo umount "${ROOTFS}/proc" || true > /dev/null
    sudo umount "${ROOTFS}/sys" || true > /dev/null
    sudo umount "${ROOTFS}/tmp" || true > /dev/null
}

mount_chroot_devs () {
    check_1_param_exist "$1"

    local ROOTFS

    ROOTFS=$1

    sudo mkdir -p "${ROOTFS}"
    sudo mount -o bind /dev "${ROOTFS}/dev"
    sudo mount -o bind /dev/pts "${ROOTFS}/dev/pts"
    sudo mount -o bind /proc "${ROOTFS}/proc"
    sudo mount -o bind /sys "${ROOTFS}/sys"
    sudo mount -o bind /tmp "${ROOTFS}/tmp"
}


function mount_image {
    echo "Mount image"
    check_2_param_exist "$1" "$2"

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

function umount_image {
    echo "Umount image"
    check_1_param_exist "$1"

    if ! [ -d "$1" ]; then
        echo "Umounting. $1 folder is not mounted."
        return
    fi

    umount_chroot_devs "$1"

    sudo umount "$1"
    rmdir "$1"
}

# sanitycheck function will return the clean path or exit with an error
# if second argument is given, path does not need to exist
# usage example: CLEANPATH="$(sanitycheck <path to check> [non_existing])"
#   on error an error message is printed to stderr and CLEANPATH is empty and return value is nonzero
#   on success CLEANPATH is the cleaned up path to <path to check> and return value is zero
function sanitycheck {
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

function download_artifactory_binary {
    echo "download_binaries"
    local DOWNLOAD_PATH
    local DESTDIR

    check_1_param_exist "$1" "$2"
    DOWNLOAD_URL="$1"
    DESTINATION="$2"

    curl -H "X-JFrog-Art-Api:${ARTIFACTORY_API_KEY:?}" -L "${DOWNLOAD_URL}" -o ${DESTINATION}

    echo "download_binaries done"
}

function compile_kernel {
    local kernel_src
    local arch
    local cross_compile
    local compile_dir
    local defconfig
    local extra_configs

    echo "compile_kernel"
    check_5_param_exist "$1" "$2" "$3" "$4" "$5" # $6 can be empty

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

    echo "compile_kernel done"
}

function install_kernel {
    local arch
    local compile_dir
    local kernel_install_dir

    echo "install_kernel"
    check_3_param_exist "$1" "$2" "$3"

    arch="$1"
    compile_dir="$2"
    kernel_install_dir="$3"

    if [ "$arch" == "arm64" ]; then
        cp "${compile_dir}/arch/arm64/boot/Image" "$kernel_install_dir"
    else
        echo "Arch: $arch is not supported" >&2
        exit 1
    fi
    echo "install_kernel done"
}

function install_kernel_modules {
    local KERNEL_SRC
    local ARCH
    local CROSS_COMPILE
    local COMPILE_DIR
    local ROOTFS
    local MNTROOTFS

    echo "install_kernel_modules"
    check_5_param_exist "$1" "$2" "$3" "$4" "$5"

    KERNEL_SRC="$1"
    ARCH="$2"
    CROSS_COMPILE="${CCACHE} $3"
    COMPILE_DIR="$4"
    ROOTFS="$5"

    MNTROOTFS="$(sanitycheck "$ROOTFS")"

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

    echo "install_kernel_modules done"
}

function compile_xen {
    echo "compile_xen"
    check_2_param_exist "$1" "$2"

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

    echo "compile_xen done"
}
