#!/bin/bash

export target=mate
export target_dir=mate-sd-image
export target_image=${target}.img
export xen_version=RELEASE-4.14.0

if [ "${target}x" == "ubuntux" ];
then
    echo "Selected:"
    echo "  Ubuntu 20.10 as dom0"
    echo "  raspOS as domU"
    dom0=ubuntu-20.10-preinstalled-desktop-arm64+raspi
    dom0_file=${dom0}.img.xz
    dom0_wget_sha256="2fa19fb53fe0144549ff722d9cd755d9c12fb508bb890926bfe7940c0b3555e8"
    dom0_wget_url=https://cdimage.ubuntu.com/releases/20.10/release/$dom0_file
    dom0_image=dom0_ubuntu20_10.img
elif [ "${target}x" == "matex" ]; then
    dom0=ubuntu-mate-20.10-desktop-arm64+raspi
    dom0_file=${dom0}.img.xz
    dom0_wget_sha256="06e26aa197eb8e7fc8144b006aab7a011fdd03990b0bf3584a95c36d55546170"
    dom0_wget_url=https://releases.ubuntu-mate.org/groovy/arm64/$dom0_file
    dom0_image=dom0_mate20_10.img
else
    echo "Not implemented"
    exit -1
fi

domu0=2020-12-02-raspios-buster-armhf
domu0_file=${domu0}.zip
domu0_wget_sha256="32034189474585c521748a6a4b21388fde9ae2c6b0c5c2d32f8abfbf508ee865"
domu0_wget_url=https://downloads.raspberrypi.org/raspios_armhf/images/raspios_armhf-2020-12-04/$domu0_file
domu0_image=domu0_raspios.img

#set -x
export xen_dom0=$dom0
export xen_dom0_file=$dom0_file
export xen_dom0_wget_sha256=$dom0_wget_sha256
export xen_dom0_wget_url=$dom0_wget_url
export xen_dom0_image=$dom0_image

export xen_domu0=$domu0
export xen_domu0_file=$domu0_file
export xen_domu0_wget_sha256=$domu0_wget_sha256
export xen_domu0_wget_url=$domu0_wget_url
export xen_domu0_image=$domu0_image
