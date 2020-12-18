#!/bin/bash

ROOT_DIR=`pwd`

set -e

CCACHE=

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    export CCACHE_DIR=`pwd`/.ccache
    export CCACHE_MAXSIZE=10G

    #ccache -s
fi

. helpers.sh

if [ "${target_dir}x" == "x" ]; then
    echo "Missing target."
    echo "Run:"
    echo "  . select_target.sh"
    exit 1
fi

LINUX_OUT_DIR=$ROOT_DIR/$target_dir/build-arm64/
DOM0_DIR=$ROOT_DIR/$target_dir/dom0/
DOMU0_DIR=$ROOT_DIR/$target_dir/domu0/
BOOT_PARTITION=$ROOT_DIR/$target_dir/boot/
KERNEL_SRC=$ROOT_DIR/linux/
XEN_SRC=$ROOT_DIR/xen-hyp/
PATCH_DIR=$ROOT_DIR/patches/

umount_chroot_devs () {
    check_1_param_exist $1

    ROOTFS=$1

    sudo umount ${ROOTFS}dev/pts || true
    sudo umount ${ROOTFS}dev || true
    sudo umount ${ROOTFS}proc || true
    sudo umount ${ROOTFS}sys || true
    sudo umount ${ROOTFS}tmp || true
}

mount_chroot_devs () {
    check_1_param_exist $1

    ROOTFS=$1

    if [ -e ${ROOTFS}dev/console ]; then
        echo .
        echo "  Chroot devs already mounted"
        echo .
        return
    fi

    sudo mkdir -p ${ROOTFS}
    sudo mount -o bind /dev ${ROOTFS}dev
    sudo mount -o bind /dev/pts ${ROOTFS}dev/pts
    sudo mount -o bind /proc ${ROOTFS}proc
    sudo mount -o bind /sys ${ROOTFS}sys
    sudo mount -o bind /tmp ${ROOTFS}tmp
}

function prepare_compile_env {
    check_2_param_exist $1 $2

    IMAGE=$1
    ROOTFS_DIR=$2

    sudo apt install qemu-user-static pkg-config

    set -x

    mount_image $IMAGE $ROOTFS_DIR
    mount_chroot_devs $ROOTFS_DIR

    sudo cp $(which qemu-aarch64-static) ${ROOTFS_DIR}usr/bin/

    # /etc/resolv.conf is required set up network for chroot.
    sudo chroot ${ROOTFS_DIR} bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

    sudo sed -i -e "s/# deb /deb /" ${ROOTFS_DIR}etc/apt/sources.list
    sudo chroot ${ROOTFS_DIR} apt-get update

    # Install the dialog package and others first to squelch some warnings
    sudo chroot ${ROOTFS_DIR} apt-get -y install dialog apt-utils
    sudo chroot ${ROOTFS_DIR} apt-get -y install uuid-dev \
        build-essential libncurses-dev pkg-config libglib2.0-dev libpixman-1-dev libc6-dev  libglib2.0-dev symlinks \
        libyajl-dev libfdt-dev libaio-dev libsystemd-dev libnl-route-3-dev zlib1g-dev \
        libusb-1.0-0-dev libpulse-dev libcapstone-dev \
        systemd systemd-sysv sysvinit-utils sudo udev rsyslog kmod util-linux sed netbase dnsutils ifupdown \
        isc-dhcp-client isc-dhcp-common less nano vim net-tools iproute2 iputils-ping libnss-mdns iw \
        software-properties-common ethtool dmsetup hostname iptables logrotate lsb-base lsb-release \
        plymouth psmisc tar tcpd symlinks \
        bridge-utils patch git \
        openssh-sftp-server remmina
    sudo chroot ${ROOTFS_DIR} apt-get clean

    sudo chroot ${ROOTFS_DIR} apt-get -y install bin86 bcc liblzma-dev ocaml python3 python3-dev gettext acpica-tools wget ftp

    umount_chroot_devs $ROOTFS_DIR
    umount_image $ROOTFS_DIR
}

function all {
    mkdir -p $BOOT_PARTITION

    compile_kernel ${KERNEL_SRC} arm64 aarch64-linux-gnu- ${LINUX_OUT_DIR} xen_defconfig
    install_kernel arm64 ${LINUX_OUT_DIR} ${BOOT_PARTITION}vmlinuz


    prepare_image ${DOM0_DIR} ${xen_dom0_file} ${xen_dom0_wget_url} ${xen_dom0_wget_sha256}
    prepare_image ${DOMU0_DIR} ${xen_domu0_file} ${xen_domu0_wget_url} ${xen_domu0_wget_sha256}

    compile_xen $XEN_SRC
    compile_xen_tools ${DOM0_DIR} arm64  $XEN_SRC

    post_image_tweaks ${DOM0_DIR}

    post_image_domu_tweaks ${DOMU0_DIR}
    echo "All done"
}

function prepare_image {
    check_4_param_exist $1 $2 $3 $4

    WORKDIR=$1
    image_file=$2
    image_url=$3
    image_compressed_sha=$4

    mkdir -p $WORKDIR
    pushd $WORKDIR > /dev/null
    if ! [ -f $image_file ]; then
        download $image_url
    fi
    if ! [ -f shaok ]; then
        check_sha "${image_compressed_sha}" "${image_file}"
    fi

    t=`basename ${image_file}`
    image_name=$(echo "$t" | sed -e 's/\.[^.]*$//')

    if [[ $image_file =~ \.zip$ ]]; then
        image_name=${image_name}.img
    fi

    if ! [ -f $image_name ]; then
        echo "Decompress ${image_file}"
        decompress_image ${image_file}
    fi

    if ! [ -f 1.img ]; then
        echo "Extract 1.img"
        decompress_image ${image_name}${extra_suffix}

        e2fsck -f 1.img
        resize2fs 1.img 10G
    fi

    ROOTFS_DIR=${WORKDIR}rootfs

    mount_image 1.img $ROOTFS_DIR
    install_kernel_modules $KERNEL_SRC arm64 aarch64-linux-gnu- $LINUX_OUT_DIR $ROOTFS_DIR

    umount_image $ROOTFS_DIR
    popd
}

function umount_all {
    WORKDIR=${DOM0_DIR}
    umount_chroot_devs ${WORKDIR}rootfs/
    umount_image ${WORKDIR}rootfs/
}

function compile_xen_tools {
   check_3_param_exist $1 $2 $3
   check_1_param_exist ${xen_version}

    WORKDIR=$1
    arch=$2
    XEN_SRC=$3

    ROOTFS_DIR=${WORKDIR}rootfs/
set -x
    if ! [ -f ${WORKDIR}prepare_compile_env.setup.done ]; then
        prepare_compile_env ${WORKDIR}1.img $ROOTFS_DIR
        touch ${WORKDIR}prepare_compile_env.setup.done
    fi

    mount_image ${WORKDIR}1.img $ROOTFS_DIR

    # Build Xen tools
    if [ "${arch}" == "arm64" ]; then
        CROSS_PREFIX=aarch64-linux-gnu
        XEN_ARCH=arm64
    else
        echo "Arch $arch is not supported"
        exit 1
    fi

    set -x

    # Use clean repo to build tools but make sure branch is same as the branch was used to build xen binary
    sudo chmod a+w ${ROOTFS_DIR}opt
    pushd ${ROOTFS_DIR}opt
    if [ ! -d xen ]; then
        git clone $XEN_SRC xen
        pushd xen
        git checkout ${xen_version}
        git apply ${PATCH_DIR}xen_*.patch
        popd
    fi
    popd

    # Change the shared library symlinks to relative instead of absolute so they play nice with cross-compiling
    sudo chroot ${ROOTFS_DIR} symlinks -c /usr/lib/${CROSS_PREFIX}/


    # TODO: This is not working at the moment. Would be much faster and preferred way to compile the tools
    if [ 0 == 1 ]; then
    pushd $XEN_SRC
    # Ask the native compiler what system include directories it searches through.
    SYSINCDIRS=$(echo $(sudo chroot ${ROOTFS_DIR} bash -c "echo | gcc -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem${ROOTFS_DIR}|"))
    SYSINCDIRSCXX=$(echo $(sudo chroot ${ROOTFS_DIR} bash -c "echo | g++ -x c++ -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem${ROOTFS_DIR}|"))

    CC="${CROSS_PREFIX}-gcc --sysroot=${ROOTFS_DIR} -nostdinc ${SYSINCDIRS} -B${ROOTFS_DIR}lib/${CROSS_PREFIX} -B${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}"
    CXX="${CROSS_PREFIX}-g++ --sysroot=${ROOTFS_DIR} -nostdinc ${SYSINCDIRSCXX} -B${ROOTFS_DIR}lib/${CROSS_PREFIX} -B${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}"
    LDFLAGS="-Wl,-rpath-link=${ROOTFS_DIR}lib/${CROSS_PREFIX} -Wl,-rpath-link=${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}"


    PKG_CONFIG=pkg-config \
    PKG_CONFIG_LIBDIR=${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}usr/share/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR=${ROOTFS_DIR} \
    LDFLAGS="${LDFLAGS}" \
    PYTHON=/bin/python3 ./configure \
        PYTHON_PREFIX_ARG=--install-layout=deb \
        --enable-systemd \
        --disable-xen \
        --enable-tools \
        --disable-docs \
        --disable-stubdom \
        --prefix=/usr \
        --with-xenstored=xenstored \
        --build=x86_64-linux-gnu \
        --host=${CROSS_PREFIX} \
        CC="${CC}" \
        CXX="${CXX}"


    PKG_CONFIG=pkg-config \
    PKG_CONFIG_LIBDIR=${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}usr/share/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR=${ROOTFS_DIR} \
    LDFLAGS="${LDFLAGS}" \
        make dist-tools \
            CROSS_COMPILE=${CROSS_PREFIX}- XEN_TARGET_ARCH=${XEN_ARCH} \
            CC="${CC}" \
            CXX="${CXX}" \
            -j $(nproc)

    sudo --preserve-env PATH=${PATH} \
    PKG_CONFIG=pkg-config \
    PKG_CONFIG_LIBDIR=${ROOTFS_DIR}usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}usr/share/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR=${ROOTFS_DIR} \
    LDFLAGS="${LDFLAGS}" \
        make install-tools \
            CROSS_COMPILE=${CROSS_PREFIX}- XEN_TARGET_ARCH=${XEN_ARCH} \
            CC="${CC}" \
            CXX="${CXX}" \
            DESTDIR=${ROOTFS_DIR}
    popd
    else
        cat > ${WORKDIR}compile_xen.sh <<EOF
#!/bin/bash

set -e
cd /opt/xen
PYTHON=/bin/python3 ./configure \
    PYTHON_PREFIX_ARG=--install-layout=deb \
    --enable-systemd \
    --disable-xen \
    --enable-tools \
    --disable-docs \
    --disable-stubdom \
    --prefix=/usr \
    --with-xenstored=xenstored

make dist-tools \
    -j $(nproc)

make install-tools \
    -j $(nproc)
EOF

        sudo chmod a+x ${WORKDIR}compile_xen.sh
        sudo cp ${WORKDIR}compile_xen.sh ${ROOTFS_DIR}
        sudo chroot ${ROOTFS_DIR} ./compile_xen.sh

    fi

    umount_image $ROOTFS_DIR
}


function post_image_tweaks {
    check_1_param_exist $1

    WORKDIR=$1

    ROOTFS_DIR=${WORKDIR}rootfs/

    mount_image ${WORKDIR}1.img $ROOTFS_DIR

    sudo chroot ${ROOTFS_DIR} systemctl enable xen-qemu-dom0-disk-backend.service
    sudo chroot ${ROOTFS_DIR} systemctl enable xen-init-dom0.service
    sudo chroot ${ROOTFS_DIR} systemctl enable xenconsoled.service
    sudo chroot ${ROOTFS_DIR} systemctl enable xendomains.service
    sudo chroot ${ROOTFS_DIR} systemctl enable xen-watchdog.service

    # It seems like the xen tools configure script selects a few too many of these backend driver modules, so we override it with a simpler list.
    # /usr/lib/modules-load.d/xen.conf
    sudo bash -c "cat >> ${ROOTFS_DIR}etc/modules" <<EOF
xen-evtchn
xen-gntdev
xen-gntalloc
xen-blkback
xen-netback
EOF

    # Fix mounting of the files
    sudo bash -c "cat > ${ROOTFS_DIR}etc/fstab" <<EOF
# UNCONFIGURED FSTAB FOR BASE SYSTEM
LABEL=writable    /     ext4    defaults,x-systemd.growfs    0 0
/swapfile         none  swap    sw    0 0
#LABEL=boot       /boot/firmware  vfat    defaults        0       1
EOF

    sudo bash -c "cat > ${ROOTFS_DIR}etc/apt/apt.conf.d/20auto-upgrades" <<EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

    # /etc/network/interfaces.d/eth0
    sudo bash -c "cat > ${ROOTFS_DIR}etc/network/interfaces.d/eth0" <<EOF
auto eth0
iface eth0 inet manual
EOF
sudo chmod 0644 ${ROOTFS_DIR}etc/network/interfaces.d/eth0

    # /etc/network/interfaces.d/xenbr0
    sudo bash -c "cat > ${ROOTFS_DIR}etc/network/interfaces.d/xenbr0" <<EOF
auto xenbr0
iface xenbr0 inet dhcp
    bridge_ports eth0
EOF
    sudo chmod 0644 ${ROOTFS_DIR}etc/network/interfaces.d/xenbr0

    # Don't wait forever and a day for the network to come online
    if [ -s ${ROOTFS_DIR}lib/systemd/system/networking.service ]; then
        sudo sed -i -e "s/TimeoutStartSec=5min/TimeoutStartSec=15sec/" ${ROOTFS_DIR}lib/systemd/system/networking.service
    fi
    if [ -s ${ROOTFS_DIR}lib/systemd/system/ifup@.service ]; then
        sudo bash -c "echo \"TimeoutStopSec=15s\" >> ${ROOTFS_DIR}lib/systemd/system/ifup@.service"
    fi

    sudo cp $ROOT_DIR/configs/domu0.cfg.usb  $ROOTFS_DIR/opt/
    install_kernel arm64 ${LINUX_OUT_DIR} $ROOTFS_DIR/opt/Image

    umount_image $ROOTFS_DIR
}

function post_image_domu_tweaks {
    check_1_param_exist $1

    WORKDIR=$1
    ROOTFS_DIR=${WORKDIR}rootfs/
    mount_image ${WORKDIR}1.img $ROOTFS_DIR

        # Fix mounting of the files
    sudo bash -c "cat > ${ROOTFS_DIR}etc/fstab" <<EOF
# UNCONFIGURED FSTAB FOR BASE SYSTEM
proc         /proc   proc    defaults    0   0
/dev/xvda    /     ext4    defaults,x-systemd.growfs    0 0
EOF

    umount_image $ROOTFS_DIR
}


$*
