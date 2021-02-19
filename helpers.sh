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

# returns 0 if function exists, 1 if not
function fn_exists {
    if [ "$(LC_ALL=C type -t "$1")" == "function" ]; then
        return 0
    else
        echo "$1: Unknown function" >&2
        return 1
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
        TPATH="$(realpath "$1" 2>/dev/null)"
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

function compile_kernel {
    local kernel_src
    local arch
    local cross_compile
    local compile_dir
    local defconfig

    echo "Compile kernel"
    check_5_param_exist "$1" "$2" "$3" "$4" "$5"

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    defconfig="$5"

    pushd "$kernel_src"
    make "O=$compile_dir" "ARCH=$arch" "CROSS_COMPILE=$cross_compile" "$defconfig"
    make "O=$compile_dir" -j 8 "ARCH=$arch" "CROSS_COMPILE=$cross_compile" Image modules dtbs \
        > "${compile_dir}/kernel_compile.log"
    popd
}

function install_kernel {
    local arch
    local compile_dir
    local kernel_install_dir

    echo "Install kernel"
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
}

function install_kernel_modules {
    local kernel_src
    local arch
    local cross_compile
    local compile_dir
    local rootfs
    local mntrootfs

    echo "Install kernel modules"
    check_5_param_exist "$1" "$2" "$3" "$4" "$5"

    kernel_src="$1"
    arch="$2"
    cross_compile="${CCACHE} $3"
    compile_dir="$4"
    rootfs="$5"

    mntrootfs="$(sanitycheck "$rootfs")"

    pushd "$kernel_src"
    # RUN in docker
    sudo make "O=$compile_dir" "ARCH=$arch" "CROSS_COMPILE=$cross_compile" "INSTALL_MOD_PATH=$mntrootfs" \
        modules_install > "${compile_dir}/modules_install.log"
    # RUN in docker end
    popd

    # Create module deps files
    echo "Create module dep files"
    KVERSION="$(cut -d "\"" -f 2 "${compile_dir}/include/generated/utsrelease.h")"
    sudo chroot "$mntrootfs" depmod -a "$KVERSION"
}

function compile_xen {
    local src

    echo "Compile xen"
    check_1_param_exist "$1"
    check_1_param_exist "${xen_version}"
    src="$1"

    # Build xen
    if [ ! -s "${src}"xen/xen ]; then
        pushd "${src}" || exit 255
        git checkout "${xen_version}"

        if [ ! -s xen/.config ]; then
            #echo "CONFIG_DEBUG=y" > xen/arch/arm/configs/arm64_defconfig
            #echo "CONFIG_SCHED_ARINC653=y" >> xen/arch/arm/configs/arm64_defconfig
            make -C xen XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
        fi
        make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dist-xen -j "$(nproc)"
        popd || exit 255
    fi
}
