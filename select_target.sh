#!/bin/bash

export BUILDOPT=MMC
export FWFDT=1 # FW defined device tree
export HYPERVISOR=XEN
export TARGET=mate
export TARGET_DIR="images/${TARGET}-images"
export TARGET_IMAGE="${TARGET}.img"
export XEN_VERSION=RELEASE-4.14.1
export KERNEL_ARCH=arm64

export DOM0_KERNEL_BUILD_BOOT="arch/${KERNEL_ARCH}/boot"
export DOM0_DTS="${DOM0_KERNEL_BUILD_BOOT}/dts"
export DOM0_DTB_RASP="${DOM0_DTS}/broadcom/bcm2711-rpi-4-b.dtb"

export XEN_DOM0_CPUCOUNT=4
export XEN_DOM0_MEMORY=4G

DOM0_KERNEL_EXTRA_CONFIGS=$(echo -e "\
# Option to disable swiotlb. There is bug in kernel's swiotlb with Xen\n\
CONFIG_XEN_FORCE_DISABLE_SWIOTLB=y" \
)

export DOM0_KERNEL_EXTRA_CONFIGS

echo ""
echo "Extra kernel configs for DOM0"
echo "${DOM0_KERNEL_EXTRA_CONFIGS}"
echo ""

case "${TARGET}" in
    ubuntu)
        echo "Selected:"
        echo "  Ubuntu 20.10 as DOM0"
        echo "  raspOS as domU"
        XEN_DOM0=ubuntu-20.10-preinstalled-desktop-arm64+raspi
        XEN_DOM0_FILE="${XEN_DOM0}.img.xz"
        XEN_DOM0_WGET_SHA256="2fa19fb53fe0144549ff722d9cd755d9c12fb508bb890926bfe7940c0b3555e8"
        XEN_DOM0_WGET_URL="https://cdimage.ubuntu.com/releases/20.10/release/${XEN_DOM0_FILE}"
        XEN_DOM0_IMAGE=dom0_ubuntu20_10.img
        ;;
    mate)
        echo "Selected:"
        echo "  Ubuntu Mate 20.10 as DOM0"
        echo "  raspOS as domU"
        XEN_DOM0=ubuntu-mate-20.10-desktop-arm64+raspi
        XEN_DOM0_FILE="${XEN_DOM0}.img.xz"
        XEN_DOM0_WGET_SHA256="06e26aa197eb8e7fc8144b006aab7a011fdd03990b0bf3584a95c36d55546170"
        XEN_DOM0_WGET_URL="https://releases.ubuntu-mate.org/groovy/arm64/${XEN_DOM0_FILE}"
        XEN_DOM0_IMAGE=dom0_mate20_10.img
        ;;
    *)
    echo "Target not supported: $TARGET"
    exit 255
    ;;
esac

echo "Using ${BUILDOPT} boot."


export XEN_DOM0
export XEN_DOM0_FILE
export XEN_DOM0_WGET_SHA256
export XEN_DOM0_WGET_URL
export XEN_DOM0_IMAGE

export XEN_DOMU0=2020-12-02-raspios-buster-armhf
export XEN_DOMU0_FILE="${XEN_DOMU0}.zip"
export XEN_DOMU0_WGET_SHA256="32034189474585c521748a6a4b21388fde9ae2c6b0c5c2d32f8abfbf508ee865"
export XEN_DOMU0_WGET_URL="https://downloads.raspberrypi.org/raspios_armhf/images/raspios_armhf-2020-12-04/${XEN_DOMU0_FILE}"
export XEN_DOMU0_IMAGE=domu0_raspios.img
