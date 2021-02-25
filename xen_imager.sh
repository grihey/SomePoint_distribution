#!/bin/bash

ROOT_DIR="$(pwd)"

set -e

CCACHE=""

if [ -x "$(command -v ccache)" ]; then
    CCACHE="ccache"
    CCACHE_DIR="$(pwd)/.ccache"
    CCACHE_MAXSIZE=10G

    export CCACHE_DIR
    export CCACHE_MAXSIZE

    #ccache -s
fi

export CCACHE

. helpers.sh
. text_generators.sh

if [ "${TARGET_DIR:?}x" == "x" ]; then
    echo "Missing target."
    echo "Run:"
    echo "  . select_target.sh"
    exit 1
fi

WORK_DIR="${ROOT_DIR}/${TARGET_DIR}"
KERNEL_SRC="${ROOT_DIR}/linux"
XEN_SRC="${ROOT_DIR}/xen-hyp"
PATCH_DIR="${ROOT_DIR}/patches"

LINUX_OUT_DIR_DOM0="${WORK_DIR}/build_${KERNEL_ARCH:?}_dom0"
LINUX_OUT_DIR_DOMU0="${WORK_DIR}/build_${KERNEL_ARCH:?}_domu0"

DOM0_DIR="${WORK_DIR}/dom0"
DOMU0_DIR="${WORK_DIR}/domu0"
BOOT_PARTITION="${WORK_DIR}/boot"

umount_chroot_devs () {
    check_1_param_exist "$1"

    local ROOTFS

    ROOTFS=$1

    sudo umount "${ROOTFS}/dev/pts" || true
    sudo umount "${ROOTFS}/dev" || true
    sudo umount "${ROOTFS}/proc" || true
    sudo umount "${ROOTFS}/sys" || true
    sudo umount "${ROOTFS}/tmp" || true
}

mount_chroot_devs () {
    check_1_param_exist "$1"

    local ROOTFS

    ROOTFS=$1

    sudo mkdir -p "${ROOTFS}" || true
    sudo mount -o bind /dev "${ROOTFS}/dev" || true
    sudo mount -o bind /dev/pts "${ROOTFS}/dev/pts" || true
    sudo mount -o bind /proc "${ROOTFS}/proc" || true
    sudo mount -o bind /sys "${ROOTFS}/sys" || true
    sudo mount -o bind /tmp "${ROOTFS}/tmp" || true
}

function prepare_compile_env {
    check_2_param_exist "$1" "$2"

    local IMAGE
    local ROOTFS_DIR

    IMAGE=$1
    ROOTFS_DIR=$2

    sudo apt install qemu-user-static pkg-config

    mount_image "$IMAGE" "$ROOTFS_DIR"
    mount_chroot_devs "$ROOTFS_DIR"

    sudo cp "$(command -v qemu-aarch64-static)" "${ROOTFS_DIR}/usr/bin/"

    # /etc/resolv.conf is required set up network for chroot.
    sudo chroot "${ROOTFS_DIR}" rm /etc/resolv.conf
    sudo chroot "${ROOTFS_DIR}" bash -c 'echo "nameserver 1.1.1.1" > /etc/resolv.conf'

    sudo sed -i -e "s/# deb /deb /" "${ROOTFS_DIR}/etc/apt/sources.list"
    sudo chroot "${ROOTFS_DIR}" apt-get update

    # Install the dialog package and others first to squelch some warnings
    sudo chroot "${ROOTFS_DIR}" apt-get -y install dialog apt-utils
    sudo chroot "${ROOTFS_DIR}" apt-get -y install uuid-dev \
        build-essential libncurses-dev pkg-config libglib2.0-dev libpixman-1-dev libc6-dev  libglib2.0-dev symlinks \
        libyajl-dev libfdt-dev libaio-dev libsystemd-dev libnl-route-3-dev zlib1g-dev \
        libusb-1.0-0-dev libpulse-dev libcapstone-dev \
        systemd systemd-sysv sysvinit-utils sudo udev rsyslog kmod util-linux sed netbase dnsutils ifupdown \
        isc-dhcp-client isc-dhcp-common less nano vim net-tools iproute2 iputils-ping libnss-mdns iw \
        software-properties-common ethtool dmsetup hostname iptables logrotate lsb-base lsb-release \
        plymouth psmisc tar tcpd symlinks \
        bridge-utils patch git \
        openssh-sftp-server remmina
    sudo chroot "${ROOTFS_DIR}" apt-get clean

    sudo chroot "${ROOTFS_DIR}" apt-get -y install bin86 bcc liblzma-dev ocaml python3 python3-dev gettext acpica-tools wget ftp

    # App dependencies
    sudo chroot "${ROOTFS_DIR}" apt-get -y install libgtk-3-dev # For Flutter
    sudo chroot "${ROOTFS_DIR}" apt-get -y install libsqlite3-dev libolm-dev # For Fluffychat (needs libolm3)

    umount_chroot_devs "$ROOTFS_DIR"
    umount_image "$ROOTFS_DIR"
}

function all {
    mkdir -p "$BOOT_PARTITION"

    compile_kernel "${KERNEL_SRC}" arm64 aarch64-linux-gnu- "${LINUX_OUT_DIR_DOM0}" xen_defconfig "${DOM0_KERNEL_EXTRA_CONFIGS}"
    install_kernel arm64 "${LINUX_OUT_DIR_DOM0}" "${BOOT_PARTITION}/vmlinuz"

    # compile kernel for domu0
    compile_kernel "${KERNEL_SRC}" arm64 aarch64-linux-gnu- "${LINUX_OUT_DIR_DOMU0}" xen_defconfig "${DOMU0_KERNEL_EXTRA_CONFIGS}"

    prepare_image "${DOM0_DIR}"  "${LINUX_OUT_DIR_DOM0}"   "${XEN_DOM0_FILE:?}" "${XEN_DOM0_WGET_URL:?}" "${XEN_DOM0_WGET_SHA256:?}" 0
    prepare_image "${DOMU0_DIR}" "${LINUX_OUT_DIR_DOMU0}"  "${XEN_DOMU0_FILE:?}" "${XEN_DOMU0_WGET_URL:?}" "${XEN_DOMU0_WGET_SHA256:?}" 1

    compile_xen "${XEN_SRC}" "${XEN_VERSION}"
    compile_xen_tools "${DOM0_DIR}" arm64  "${XEN_SRC}"

    post_image_tweaks "${DOM0_DIR}"

    post_image_domu_tweaks "${DOMU0_DIR}"

    prepare_boot "$BOOT_PARTITION"

    echo "All done"
}

function prepare_boot {
    check_1_param_exist "$1"

    local BOOTFS

    BOOTFS=$1

    case "${BUILDOPT}" in
    MMC|USB)
        ubootsource > "${WORK_DIR}/boot.source"
        mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d "${WORK_DIR}/boot.source" "${BOOTFS}/boot.scr"
        ;;
    # Not supported at the moment
    #TFTP)
    #    ubootstub > "${WORK_DIR}"boot.source
    #    mkimage -A arm64 -T script -C none -a 0x2400000 -e 0x2400000 -d "${WORK_DIR}"boot.source "${WORK_DIR}"boot.scr
    #    ubootsource > "${WORK_DIR}"boot2.source
    #    mkimage -A arm64 -T script -C none -a 0x100000 -e 0x100000 -d "${WORK_DIR}"boot2.source "${WORK_DIR}"boot2.scr
    #;;
    *)
        echo "Invalid BUILDOPT <${BUILDOPT}> setting" >&2
        exit 1
    ;;
    esac

    config_txt > "${BOOTFS}/config.txt"
    cp u-boot.bin "${BOOTFS}"
    cp "${XEN_SRC}/xen/xen" "${BOOTFS}"

    cp "${LINUX_OUT_DIR_DOM0}/${DOM0_DTB_RASP:?}" "$BOOTFS"
    cp -r "${LINUX_OUT_DIR_DOM0}/${DOM0_DTS:?}/overlays" "$BOOTFS"
    cp usbfix/fixup4.dat "$BOOTFS"
    cp usbfix/start4.elf "$BOOTFS"
}

function prepare_image {
    check_6_param_exist "$1" "$2" "$3" "$4" "$5" "$6"

    local WORKDIR
    local LINUX_OUT_DIR
    local IMAGE_FILE
    local IMAGE_URL
    local IMAGE_NAME
    local IMAGE_COMPRESSED_SHA
    local IS_DOMU
    local ROOTFS_DIR

    WORKDIR=$1
    LINUX_OUT_DIR=$2
    IMAGE_FILE=$3
    IMAGE_URL=$4
    IMAGE_COMPRESSED_SHA=$5
    IS_DOMU=$6

    mkdir -p "$WORKDIR"
    pushd "$WORKDIR" > /dev/null
    if ! [ -f "$IMAGE_FILE" ]; then
        download "$IMAGE_URL"
    fi
    if ! [ -f shaok ]; then
        check_sha "${IMAGE_COMPRESSED_SHA}" "${IMAGE_FILE}"
    fi

    t=$(basename "${IMAGE_FILE}")
    # Copy the name expect last .zip
    IMAGE_NAME=$(echo "$t" | sed -e 's/\.[^.]*$//')

    if [[ "${IMAGE_FILE}" =~ \.zip$ ]]; then
        IMAGE_NAME="${IMAGE_NAME}.img"
    fi

    if ! [ -f "${IMAGE_NAME}" ]; then
        echo "Decompress ${IMAGE_FILE}"
        decompress_image "${IMAGE_FILE}"
    fi

    if ! [ -f 1.img ]; then
        echo "Extract 1.img"
        decompress_image "${IMAGE_NAME}"

        # only resize dom0. Space is needed for compiling Xen.
        if [ "$IS_DOMU" == "0" ]; then
            e2fsck -f 1.img
            resize2fs 1.img 10G
        fi
    fi

    ROOTFS_DIR=${WORKDIR}/rootfs

    mount_image 1.img "$ROOTFS_DIR"
    install_kernel_modules "$KERNEL_SRC" arm64 aarch64-linux-gnu- "$LINUX_OUT_DIR" "$ROOTFS_DIR"

    umount_image "$ROOTFS_DIR"
    popd
}

function umount_all {
    local WORKDIR

    WORKDIR="${DOM0_DIR}"
    umount_chroot_devs "${WORKDIR}/rootfs/"
    umount_image "${WORKDIR}/rootfs/"
}

function compile_xen_tools {
    check_3_param_exist "$1" "$2" "$3"

    local WORKDIR
    local ARCH
    local XEN_SRC
    local ROOTFS_DIR
    local CROSS_PREFIX
    local XEN_ARCH

    WORKDIR=$1
    ARCH=$2
    XEN_SRC=$3

    ROOTFS_DIR="${WORKDIR}/rootfs"
    if ! [ -f "${WORKDIR}/prepare_compile_env.setup.done" ]; then
        prepare_compile_env "${WORKDIR}/1.img" "$ROOTFS_DIR"
        touch "${WORKDIR}/prepare_compile_env.setup.done"
    fi

    mount_image "${WORKDIR}/1.img" "$ROOTFS_DIR"

    # Build Xen tools
    if [ "${ARCH}" == "arm64" ]; then
        CROSS_PREFIX=aarch64-linux-gnu
        XEN_ARCH=arm64
    else
        echo "Arch $ARCH is not supported"
        exit 1
    fi

    # TODO: This is not working at the moment. Would be much faster and preferred way to compile the tools
    if [ 0 == 1 ]; then
        # Change the shared library symlinks to relative instead of absolute so they play nice with cross-compiling
        sudo chroot "${ROOTFS_DIR}" symlinks -c "/usr/lib/${CROSS_PREFIX:?}/"

        pushd "$XEN_SRC" || exit 255
        # Ask the native compiler what system include directories it searches through.
        SYSINCDIRS=$(sudo chroot "${ROOTFS_DIR}" bash -c "echo | gcc -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem ${ROOTFS_DIR}/|")
        SYSINCDIRSCXX=$(sudo chroot "${ROOTFS_DIR}" bash -c "echo | g++ -x c++ -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem ${ROOTFS_DIR}/|")
        CC="${CROSS_PREFIX}-gcc --sysroot=${ROOTFS_DIR} -B${ROOTFS_DIR}/lib/${CROSS_PREFIX} -B${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}"
        CXX="${CROSS_PREFIX}-g++ --sysroot=${ROOTFS_DIR} -B${ROOTFS_DIR}/lib/${CROSS_PREFIX} -B${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}"
        LDFLAGS="-Wl,-rpath-link=${ROOTFS_DIR}/lib/${CROSS_PREFIX} -Wl,-rpath-link=${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}"

        PKG_CONFIG=pkg-config \
        PKG_CONFIG_LIBDIR=${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig \
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
        PKG_CONFIG_LIBDIR="${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="${ROOTFS_DIR}" \
        LDFLAGS="${LDFLAGS}" \
            make dist-tools \
                CROSS_COMPILE="${CROSS_PREFIX}-" XEN_TARGET_ARCH="${XEN_ARCH}" \
                CC="${CC}" \
                CXX="${CXX}" \
                -j "$(nproc)"

        sudo --preserve-env PATH="${PATH}" \
        PKG_CONFIG=pkg-config \
        PKG_CONFIG_LIBDIR="${ROOTFS_DIR}/usr/lib/${CROSS_PREFIX}/pkgconfig:${ROOTFS_DIR}/usr/share/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="${ROOTFS_DIR}" \
        LDFLAGS="${LDFLAGS}" \
            make install-tools \
                CROSS_COMPILE="${CROSS_PREFIX}-" XEN_TARGET_ARCH="${XEN_ARCH}" \
                CC="${CC}" \
                CXX="${CXX}" \
                DESTDIR="${ROOTFS_DIR}"
        popd
    else
        # Use clean repo to build tools but make sure branch is same as the branch was used to build xen binary
        sudo chmod a+w "${ROOTFS_DIR}/opt"
        pushd "${ROOTFS_DIR}/opt" || exit 255
        if [ ! -d xen ]; then
            git clone "$XEN_SRC" xen
            pushd xen || exit 255
            git checkout "${XEN_VERSION:?}"
            popd || exit 255
        fi

        if [ ! -f xen/patches_applied.done ]; then
            pushd xen || exit 255
            # Cannot surround the whole second parameter.
            git apply "${PATCH_DIR}"/xen_*.patch
            touch patches_applied.done
            popd || exit 255
        fi

        cat > "${WORKDIR}/compile_xen.sh" <<EOF
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
        sudo chmod a+x "${WORKDIR}/compile_xen.sh"
        sudo cp "${WORKDIR}/compile_xen.sh" "${ROOTFS_DIR}"
        sudo chroot "${ROOTFS_DIR}" ./compile_xen.sh
    fi

    umount_image "$ROOTFS_DIR"
}


function post_image_tweaks {
    check_1_param_exist "$1"

    local WORKDIR
    local ROOTFS_DIR

    WORKDIR=$1
    ROOTFS_DIR="${WORKDIR}/rootfs/"

    mount_image "${WORKDIR}/1.img" "$ROOTFS_DIR"

    sudo chroot "${ROOTFS_DIR}" systemctl enable xen-qemu-dom0-disk-backend.service
    sudo chroot "${ROOTFS_DIR}" systemctl enable xen-init-dom0.service
    sudo chroot "${ROOTFS_DIR}" systemctl enable xenconsoled.service
    sudo chroot "${ROOTFS_DIR}" systemctl enable xendomains.service
    sudo chroot "${ROOTFS_DIR}" systemctl enable xen-watchdog.service

    # It seems like the xen tools configure script selects a few too many of these backend driver modules, so we override it with a simpler list.
    # /usr/lib/modules-load.d/xen.conf
    sudo bash -c "cat >> ${ROOTFS_DIR}/etc/modules" <<EOF
xen-evtchn
xen-gntdev
xen-gntalloc
xen-blkback
xen-netback
EOF

    # Fix mounting of the files
    sudo bash -c "cat > ${ROOTFS_DIR}/etc/fstab" <<EOF
# UNCONFIGURED FSTAB FOR BASE SYSTEM
LABEL=writable    /     ext4    defaults,x-systemd.growfs    0 0
/swapfile         none  swap    sw    0 0
#LABEL=boot       /boot/firmware  vfat    defaults        0       1
EOF

    sudo bash -c "cat > ${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades" <<EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

    # /etc/network/interfaces.d/eth0
    sudo bash -c "cat > ${ROOTFS_DIR}/etc/network/interfaces.d/eth0" <<EOF
auto eth0
iface eth0 inet manual
EOF
sudo chmod 0644 "${ROOTFS_DIR}/etc/network/interfaces.d/eth0"

    # /etc/network/interfaces.d/xenbr0
    sudo bash -c "cat > ${ROOTFS_DIR}/etc/network/interfaces.d/xenbr0" <<EOF
auto xenbr0
iface xenbr0 inet dhcp
    bridge_ports eth0
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0
EOF
    sudo chmod 0644 "${ROOTFS_DIR}/etc/network/interfaces.d/xenbr0"

    # Don't wait forever and a day for the network to come online
    if [ -s "${ROOTFS_DIR}/lib/systemd/system/networking.service" ]; then
        sudo sed -i -e "s/TimeoutStartSec=5min/TimeoutStartSec=15sec/" "${ROOTFS_DIR}/lib/systemd/system/networking.service"
    fi
    if [ -s "${ROOTFS_DIR}"lib/systemd/system/ifup@.service ]; then
        sudo bash -c "echo \"TimeoutStopSec=15s\" >> ${ROOTFS_DIR}/lib/systemd/system/ifup@.service"
    fi

    domu_config > "${ROOTFS_DIR}/opt/domu.cfg"
    install_kernel arm64 "${LINUX_OUT_DIR_DOMU0}" "$ROOTFS_DIR/opt/Image"

    umount_image "$ROOTFS_DIR"
}

function post_image_domu_tweaks {
    check_1_param_exist "$1"

    local WORKDIR
    local ROOTFS_DIR

    WORKDIR=$1
    ROOTFS_DIR="${WORKDIR}/rootfs/"
    mount_image "${WORKDIR}/1.img" "$ROOTFS_DIR"

        # Fix mounting of the files
    sudo bash -c "cat > ${ROOTFS_DIR}/etc/fstab" <<EOF
# UNCONFIGURED FSTAB FOR BASE SYSTEM
proc         /proc   proc    defaults    0   0
/dev/xvda    /     ext4    defaults,x-systemd.growfs    0 0
EOF

    umount_image "$ROOTFS_DIR"
}


"$*"
