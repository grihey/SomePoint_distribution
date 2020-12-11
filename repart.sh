#!/bin/bash

DEVICE=/dev/sda
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
        echo "Usage:"
        echo "    $0 [-b|--boot <boot fs size>] [-r|-root <root fs size>] [-d|--domu <domu fs size>] [-y|--yes] [--force] [device]"
        echo ""
        echo "Example:"
        echo "    $0 -b 512M -r 4G -d 4G -y /dev/sda"
        echo ""
        echo "Default device = /dev/sda"
        echo "Default boot fs size = 128M"
        echo "Default root fs size = 1G"
        echo "Default domu fs size = 1G"
	echo ""
        echo 'Use -d "" or --domu "" to use all remaining space on device for domu partition'
        echo "-y or --yes = Don't ask for confirmation"
        echo "--force = Force partition creation even though device seems to be mounted (Please know what you're doing!)"
	echo ""
        exit 1
        ;;
	-y|--yes)
	CONFIRM=N
	shift # past argument
	;;
        --force)
        FORCED=Y
        shift # past argument
        ;;
        *)    # unknown option
        DEVICE=$1
        shift # past argument
        ;;
   esac
done

if [ "$FORCED" != "Y" ]; then
    mount | grep -q ${DEVICE}
    if [ $? -eq 0 ]; then
       echo "${DEVICE} seems to be mounted, aborting"
       exit 1
    fi
fi

echo "      Device = ${DEVICE}"
echo "Boot FS size = ${BOOTSIZ}"
echo "Root FS size = ${ROOTSIZ}"
echo "Domu FS size = ${DOMUSIZ:-fill device}"

if [ "$CONFIRM" == "Y" ]; then
    echo "THIS WILL DESTROY ANY DATA ON SELECTED DEVICE!"
    read -p " Do you really want to continue? (y/N): " I
    if [ "$I" != "y" -a "$I" != "Y" ]; then
	echo Canceled
        exit 1
    fi
fi

if [ "$DOMUSIZ" != "" ]; then
    DOMUSIZ=+${DOMUSIZ}
fi

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk ${DEVICE}
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

# Do partition probe just in case
sudo partprobe ${DEVICE}

# Create FAT32 boot FS
sudo mkdosfs -F 32 ${DEVICE}1

# Create EXT4 root FS
sudo mkfs.ext4 -F ${DEVICE}2

# Create EXT4 domu FS
sudo mkfs.ext4 -F ${DEVICE}3
