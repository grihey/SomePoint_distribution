#!/bin/bash

set -e

UBASEDIR=ubuntu-base-20.04.1-base-arm64
UBASETAR=$UBASEDIR.tar.gz

# Create a build environment based on Ubuntu 20.04.1.
if [ ! -f $UBASETAR ]; then
    echo "wget Ubuntu 20.04.1"
    wget http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/$UBASETAR
fi

if [ ! -d $UBASEDIR ]; then
    echo "Extracting Ubuntu tar"
    mkdir -p $UBASEDIR
    tar -xzvf $UBASETAR -C $UBASEDIR
fi

# Get QEMU sources (https://www.qemu.org/download/#source)
if [ ! -d qemu ]; then
    echo "Cloning qemu"
    git clone https://git.qemu.org/git/qemu.git
    cd qemu
    echo "Qemu git submodule init"
    git submodule init
    echo "Qemu git submodule update"
    git submodule update --recursive
    cd ..
else
    cd qemu
    echo "Qemu git pull"
    git pull
    echo "Qemu git submodule update"
    git submodule update --recursive
    cd ..
fi

# Install some tools for chroot usage
echo "Install some host tools if not installed"
sudo apt install qemu binfmt-support qemu-user-static

# Copy the interpreter (QEMU) to your base image folder structure
echo "Copy host Qemu binary"
cp /usr/bin/qemu-aarch64-static ./$UBASEDIR/usr/bin

# Copy resolv.conf  for chroot networking
echo "Copy resolv.conf"
cp /etc/resolv.conf ./$UBASEDIR/etc

# Create script for running inside chroot ---------------------------------
echo "Create script for running inside chroot"
cat << EOF > ./$UBASEDIR/part2.sh
#!/bin/bash

set -e
set -x

# Just to prevent issues with apt
chmod 1777 /tmp

# Update apt repositories & upgrade packages within chroot.
apt update
apt upgrade

# Within chroot install some tools and dependencies (these vary depending on the QEMU configuration).
# The following should apply for building this example.
apt install python3 make ninja-build build-essential pkg-config git libglib2.0-dev libfdt-dev \
libpixman-1-dev zlib1g-dev libspice-server-dev libspice-protocol-dev libasound2-dev

# Within chroot configure and build QEMU.
# There are several configuration options for QEMU based on the features needed.
# This example builds a KVM enabled QEMU with SPICE support.
mkdir -p /qemu/build/arm64-kvm-spice
cd /qemu/build/arm64-kvm-spice
#../../configure --enable-kvm --enable-spice --enable-fdt --target-list=aarch64-softmmu --disable-werror
../../configure --enable-kvm --enable-fdt --target-list=aarch64-softmmu --disable-debug-info --disable-werror --static
make -j4
EOF
#--------------------------------------------------------------------------

# Make the script executable
echo "Make script executable"
chmod a+x ./$UBASEDIR/part2.sh

#Create a qemu mount point
echo "Create qemu mount point"
mkdir -p ./$UBASEDIR/qemu

set +e
#Start up the chroot
findmnt ./$UBASEDIR/qemu > /dev/null
if [ $? -ne 0 ]; then
    echo "Mounting qemu build dir under ubuntu chroot"
    sudo mount -o bind ./qemu ./$UBASEDIR/qemu
fi
findmnt ./$UBASEDIR/dev > /dev/null
if [ $? -ne 0 ]; then
    echo "Mounting devices under ubunut chroot"
    sudo mount -o bind /dev ./$UBASEDIR/dev
fi

echo "Running part2.sh in chroot"
sudo LC_ALL=C chroot ./$UBASEDIR /part2.sh

echo "Unmounting devices"
sudo umount ./$UBASEDIR/dev
echo "Unmounting qemu"
sudo umount ./$UBASEDIR/qemu

echo "Copying efi-virtio.rom"
cp -f qemu/pc-bios/efi-virtio.rom .
echo "copying qemu-system-aarch64"
cp -f qemu/build/arm64-kvm-spice/aarch64-softmmu/qemu-system-aarch64 .

