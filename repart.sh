#!/bin/bash

# Calculates actual number of bytes from strings like '4G' and '23M' plain numbers are sectors (512 bytes)
function actual_value {
    local LCH=${1: -1}
    case $LCH in
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

function show_help {
    echo "Usage:"
    echo "    $0 [-b|--boot <boot fs size>] [-r|-root <root fs size>] [-d|--domu <domu fs size>] [-y|--yes] [--force] <device>"
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

if [ $# -eq 0 ]; then
    show_help
fi

DEVICE=/dev/null
BOOTSIZ=128M
ROOTSIZ=1G
DOMUSIZ=1G
CONFIRM=Y
FORCED=N

while [ $# -gt 0 ]; do
    case $1 in
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
        -h|--help)
	show_help
        ;;
	-y|--yes)
	CONFIRM=N
	shift # past argument
	;;
        --force)
        FORCED=Y
        shift # past argument
        ;;
        *)    # device name
        DEVICE=$1
        shift # past argument
        ;;
   esac
done

if [ "$FORCED" != "Y" ]; then
    mount | grep -q $DEVICE
    if [ $? -eq 0 ]; then
       echo "${DEVICE} seems to be mounted, aborting"
       exit 1
    fi
fi

if [ -d "$DEVICE" ]; then
    echo "${DEVICE} is a directory, aborting"
    exit 2
fi

if [ -c "$DEVICE" ]; then
    echo "${DEVICE} is a character device, aborting"
    exit 3
fi

if [ ! -b "$DEVICE" -a -z "$DOMUSIZ" ]; then
    echo "Domu Fs size cannot be 'fill device' when using an image file"
    exit 4
fi

AB=`actual_value $BOOTSIZ`
if [ $AB -eq 0 ]; then
    echo "Invalid boot fs size"
    exit 5
fi

AR=`actual_value $ROOTSIZ`
if [ $AR -eq 0 ]; then
    echo "Invalid root fs size"
    exit 6
fi

if [ -n "$DOMUSIZ" ]; then
    AD=`actual_value $DOMUSIZ`
    if [ $AD -eq 0 ]; then
        echo "Invalid domu fs size"
        exit 7
    fi
fi

echo "      Device = ${DEVICE}"
echo "Boot FS size = ${BOOTSIZ}"
echo "Root FS size = ${ROOTSIZ}"
echo "Domu FS size = ${DOMUSIZ:-fill device}"

if [ "$CONFIRM" == "Y" ]; then
    echo "THIS WILL DESTROY ANY DATA IN SELECTED DEVICE OR IMAGE FILE!"
    read -p " Do you really want to continue? (y/N): " I
    if [ "$I" != "y" -a "$I" != "Y" ]; then
	echo Canceled
        exit 8
    fi
fi

if [ ! -b "$DEVICE" ]; then
    DEVSIZ=$(($AB+$AR+$AD))
    truncate -s $DEVSIZ $DEVICE
    DOMUSIZ=""
fi

if [ -n "$DOMUSIZ" ]; then
    DOMUSIZ=+$DOMUSIZ
fi

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk $DEVICE
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
    sudo partprobe $DEVICE

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
    KPARTXOUT=`sudo kpartx -l "$DEVICE" 2> /dev/null`

    DP1=/dev/mapper/`grep "p1 " <<< "$KPARTXOUT" | cut -d " " -f1`
    DP2=/dev/mapper/`grep "p2 " <<< "$KPARTXOUT" | cut -d " " -f1`
    DP3=/dev/mapper/`grep "p3 " <<< "$KPARTXOUT" | cut -d " " -f1`

    sudo kpartx -a $DEVICE
fi

# Create FAT32 boot FS
sudo mkdosfs -F 32 $DP1

# Create EXT4 root FS
sudo mkfs.ext4 -F $DP2

# Create EXT4 domu FS
sudo mkfs.ext4 -F $DP3

sudo sync

if [ ! -b "$DEVICE" ]; then
     sudo kpartx -d $DEVICE
fi
