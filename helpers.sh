#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh
# compile <args>

function defconfig {
    echo "Creating .setup_sh_config with defaults"
    cp -f default_setup_sh_config .setup_sh_config
}

# returns 0 if function exists, 1 if not
function fn_exists {
    if [ "x$(LC_ALL=C type -t $1)" == "xfunction" ]; then
       return 0
    else
       echo "$1: Unknown function" >&2
       return 1
    fi
}

function check_param_exist {
    if [ "$1x" == "x" ]; then
        echo "Parameter not defined"
        exit 1
    fi
}

function check_1_param_exist {
    check_param_exist $1
}

function check_2_param_exist {
    check_param_exist $1
    check_param_exist $2
}

function check_3_param_exist {
    check_param_exist $1
    check_param_exist $2
    check_param_exist $3
}

function check_4_param_exist {
    check_param_exist $1
    check_param_exist $2
    check_param_exist $3
    check_param_exist $4
}

function check_5_param_exist {
    check_param_exist $1
    check_param_exist $2
    check_param_exist $3
    check_param_exist $4
    check_param_exist $5
}

function check_sha {
    # $1 is sha
    # $2 is file
    check_2_param_exist $1 $2
    echo "${1} *${2}" | shasum -a 256 --check -s --strict
    ok=$?
    echo "val: <$ok>"
    if [ "$ok" == "0" ]; then
        echo 1 > shaok
    fi
}

function download {
    check_1_param_exist $1
    wget $1
}

function decompress_xz {
    check_1_param_exist $1

    xz -dk $1
}

function decompress_image {
    check_1_param_exist $1

    echo $1

    7z e $1 || true
}

function mount_image {
    echo "Mount image"
    check_2_param_exist $1 $2

    if [ -d $2 ]; then
        echo "Mounting: $1 to $2 -folder. Already mounted."
        #return
    fi
    mkdir -p $2
    if [ ! -f $1 ]; then
        exit 1
    fi
    sudo mount $1 $2 || true
}

function umount_image {
    echo "Umount image"
    check_1_param_exist $1

    if ! [ -d $1 ]; then
        echo "Umounting. $1 folder is not mounted."
        return
    fi
    sudo umount $1
    rmdir $1
}

# sanitycheck function will return the clean path or exit with an error
# usage example: CLEANPATH=`sanitycheck <path to check>`
#   on error an error message is printed to stderr and CLEANPATH is empty and return value is nonzero
#   on success CLEANPATH is the cleaned up path to <path to check> and return value is zero
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

function compile_kernel {
    echo "Compile kernel"
    check_5_param_exist $1 $2 $3 $4 $5

    kernel_src=$1
    arch=$2
    cross_compile="${CCACHE} $3"
    compile_dir=$4
    defconfig=$5

    pushd $kernel_src
    # RUN in docker
    make O=$compile_dir ARCH=$arch CROSS_COMPILE="$cross_compile" $defconfig
    make O=$compile_dir -j 8 ARCH=$arch CROSS_COMPILE="$cross_compile" Image modules dtbs \
        > ${compile_dir}kernel_compile.log
    popd
    # RUN in docker end
}

function install_kernel {
    echo "Install kernel"
    check_3_param_exist $1 $2 $3

    arch=$1
    compile_dir=$2
    kernel_install_dir=$3

    if [ "$arch" == "arm64" ]; then
        cp ${compile_dir}arch/arm64/boot/Image $kernel_install_dir
    else
        echo "Arch: $arch is not supported"
        exit 1
    fi
}

function install_kernel_modules {
    echo "Install kernel modules"
    check_5_param_exist $1 $2 $3 $4 $5

    kernel_src=$1
    arch=$2
    cross_compile="${CCACHE} $3"
    compile_dir=$4
    rootfs=$5

    mntrootfs=`sanitycheck $rootfs`

    pushd $kernel_src
    # RUN in docker
    sudo make O=$compile_dir ARCH=$arch CROSS_COMPILE="$cross_compile" INSTALL_MOD_PATH=$mntrootfs \
        modules_install > ${compile_dir}modules_install.log
    # RUN in docker end
    popd

    # Create module deps files
    sudo chroot $mntrootfs depmod -a 5.9.6-v8+
}

function compile_xen {
    echo "Compile xen"
    check_1_param_exist $1
    check_1_param_exist ${xen_version}
    src=$1

    # Build xen
    if [ ! -s ${src}xen/xen ]; then
        pushd ${src}
        git checkout ${xen_version}
        if [ ! -s xen/.config ]; then
            #echo "CONFIG_DEBUG=y" > xen/arch/arm/configs/arm64_defconfig
            #echo "CONFIG_SCHED_ARINC653=y" >> xen/arch/arm/configs/arm64_defconfig
            make -C xen XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
        fi
        make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dist-xen -j $(nproc)
        popd
    fi
}
