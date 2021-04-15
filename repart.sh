#!/bin/bash

set -e

. helpers.sh
Load_config

function Show_help {
    echo "Usage:"
    echo "    $0 [-b|--boot <boot fs size>] [-r|-root <root fs size>] [-d|--domu <domu fs size>] [-y|--yes] [--force] <device>"
    echo "       [-ir|--image-root <root image>"
    echo "       [-id|--image-domu <domu image>"
    echo ""
    echo "Examples:"
    echo "    $0 -b 512M -r 4G -d 4G -y /dev/sda"
    echo "    $0 -b 256M -r 2G -d 1500M image.file"
    echo ""
    echo "Default boot fs size = 128M"
    echo "Default root fs size = 1G"
    echo "Default domu fs size = 1G"
    echo ""
    echo "Plain numbers without trailing G or M are interpreted as sectors (512 bytes)"
    echo 'Use -d "" or --domu "" to use all remaining space on device for domu partition'
    echo "-y or --yes = Don't ask for confirmation"
    echo "--force = Force partition creation even though device seems to be mounted (Please know what you're doing!)"
    echo ""
    exit 1
}

if [ "$#" -eq 0 ]; then
    Show_help >&2
fi

DEVICE=/dev/null
BOOTSIZ=128M
ROOTSIZ=1G
DOMUSIZ=1G
CONFIRM=Y
FORCED=N
IMAGE_ROOT=""
IMAGE_DOMU=""

while [ "$#" -gt 0 ]; do
    case "$1" in
    -b|--boot)
        BOOTSIZ="$2"
        shift # past argument
        shift # past value
    ;;
    -r|--root)
        ROOTSIZ="$2"
        shift # past argument
        shift # past value
    ;;
    -d|--domu)
        DOMUSIZ="$2"
        shift # past argument
        shift # past value
    ;;
    -ir|--image-root)
        IMAGE_ROOT="$2"
        shift # past argument
        shift # past value
    ;;
    -id|--image-domu)
        IMAGE_DOMU="$2"
        shift # past argument
        shift # past value
    ;;
    -h|--help)
        Show_help
    ;;
    -y|--yes)
        CONFIRM=N
        shift # past argument
    ;;
    --force)
        FORCED=Y
        shift # past argument
    ;;
    check_script)
        Shellcheck_bashate repart.sh helpers.sh default_setup_sh_config
        exit $?
    ;;
    *)    # device name and invalid argument
        # Argument that starts with "-" have been prosessed already.
        if [[ $1 == -* ]]; then
            echo "Argument <$1> not supported. You might have missed a space before size value!"
            exit 1
        fi
        DEVICE="$1"
        shift # past argument
    ;;
    esac
done

if [ "$FORCED" != "Y" ]; then
    if mount | grep -q "$DEVICE"; then
        echo "${DEVICE} seems to be mounted, aborting" >&2
        exit 1
    fi
fi

if [ -d "$DEVICE" ]; then
    echo "${DEVICE} is a directory, aborting" >&2
    exit 2
fi

if [ -c "$DEVICE" ]; then
    echo "${DEVICE} is a character device, aborting" >&2
    exit 3
fi

if [ ! -b "$DEVICE" ] && [ -z "$DOMUSIZ" ]; then
    echo "Domu Fs size cannot be 'fill device' when using an image file" >&2
    exit 4
fi

AB="$(Actual_value "$BOOTSIZ")"
if [ "$AB" -eq 0 ]; then
    echo "Invalid boot fs size" >&2
    exit 5
fi

AR="$(Actual_value "$ROOTSIZ")"
if [ "$AR" -eq 0 ]; then
    echo "Invalid root fs size" >&2
    exit 6
fi

if [ -n "$DOMUSIZ" ]; then
    AD="$(Actual_value "$DOMUSIZ")"
    if [ "$AD" -eq 0 ]; then
        echo "Invalid domu fs size" >&2
        exit 7
    fi
fi

if [ -n "$IMAGE_ROOT" ]; then
    if [ ! -f "$IMAGE_ROOT" ]; then
        echo "Root image <$IMAGE_ROOT> not found"
        exit 8
    fi
fi

if [ -n "$IMAGE_DOMU" ]; then
    if [ ! -f "$IMAGE_DOMU" ]; then
        echo "Domu image <$IMAGE_DOMU> not found"
        exit 9
    fi
fi

echo "      Device = ${DEVICE}"
echo "Boot FS size = ${BOOTSIZ}"
echo "Root FS size = ${ROOTSIZ}"
echo "Domu FS size = ${DOMUSIZ:-fill device}"
if [ -n "$IMAGE_ROOT" ]; then
    echo "  Root Image = ${IMAGE_ROOT}"
fi
if [ -n "$IMAGE_DOMU" ]; then
    echo "  Domu Image = ${IMAGE_DOMU}"
fi

if [ "$CONFIRM" == "Y" ]; then
    echo "THIS WILL DESTROY ANY DATA IN SELECTED DEVICE OR IMAGE FILE!"
    read -rp " Do you really want to continue? (y/N): " I
    if [ "$I" != "y" ] && [ "$I" != "Y" ]; then
    echo Canceled
        exit 8
    fi
fi

if [ ! -b "$DEVICE" ]; then
    DEVSIZ="$((AB+AR+AD))"
    truncate -s "$DEVSIZ" "$DEVICE"
    DOMUSIZ=""
fi

if [ -n "$DOMUSIZ" ]; then
    DOMUSIZ="+$DOMUSIZ"
fi

# Sed magic here used to remove comments from the here document
# Avoiding the here document would require creating a temp file
# $SUDOCMD is intentionally unquoted
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk "$DEVICE"
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk
  +${BOOTSIZ} # boot parttion
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
  +${ROOTSIZ} # root partition
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition
  ${DOMUSIZ} # domu partition
  t # Change type
  1 # Partition 1
  c # FAT32
  a # make a partition bootable
  1 # bootable partition is partition 1 -- /dev/sda1
  p # print the in-memory partition table
  w # write the partition table
EOF

if [ -b "$DEVICE" ]; then
    # Do partition probe just in case
    sudo partprobe "$DEVICE"

    # Add 'p' to partition device name, if main device name ends in number (e.g. /dev/mmcblk0)
    if [[ "${DEVICE: -1}" =~ [0-9] ]]; then
        MIDP="p"
    else
        MIDP=""
    fi

    DP1="${DEVICE}${MIDP}1"
    DP2="${DEVICE}${MIDP}2"
    DP3="${DEVICE}${MIDP}3"
else
    # Loop device partitions if it
    KPARTXOUT="$(sudo kpartx -l "$DEVICE" 2> /dev/null)"

    DP1="/dev/mapper/$(grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1)"
    DP2="/dev/mapper/$(grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1)"
    DP3="/dev/mapper/$(grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1)"

    sudo kpartx -a "$DEVICE"
fi

# Create FAT32 boot FS
sudo mkdosfs -F 32 "$DP1"

if [ -f "$IMAGE_DOMU" ]; then
    echo "Flashing image $IMAGE_ROOT to $DP2"
    sudo dd if="$IMAGE_ROOT" of="$DP2" bs=4k
else
    # Create EXT4 root FS
    sudo mkfs.ext4 -F "$DP2"
fi

if [ -f "$IMAGE_DOMU" ]; then
    echo "Flashing image $IMAGE_DOMU to $DP3"
    sudo dd if="$IMAGE_DOMU" of="$DP3" bs=4k
else
    # Create EXT4 domu FS
    sudo mkfs.ext4 -F "$DP3"
fi

sudo sync

if [ ! -b "$DEVICE" ]; then
    sudo kpartx -d "$DEVICE"
fi
