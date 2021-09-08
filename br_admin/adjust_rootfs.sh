#!/bin/bash

TCDIST_VM_NAME="br_admin"

# Include generic rootfs adjustment functions
. "${TCDIST_DIR}/adjust_rootfs.sh" "$1"

Arfs_load_config
# Variable purposefully unquoted, it contains list of space separated options
# shellcheck disable=SC2086
Arfs_apply ${ARFS_OPTIONS} "$@"

# Insert vm specific adjustments here

# upXtreme extras
if [ "${TCDIST_ARCH}_${TCDIST_PLATFORM}" == "x86_upxtreme" ]; then
    e2cp "${2}:/etc/fstab" fstab.tmp
    echo "debugfs    /sys/kernel/debug      debugfs  defaults  0 0" >> fstab.tmp
    e2cp fstab.tmp "${2}:/etc/fstab"
    rm fstab.tmp
fi

# Copy over any system testing related items
if [ "$TCDIST_SYS_TEST" = "1" ] ; then
    set -x
    # Uncomment below line to enable virt tools debug
    #export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
    output_dir="${TCDIST_OUTPUT}/br_admin/output_${TCDIST_ARCH}_${TCDIST_PLATFORM}"
    image_dir="${output_dir}/images"
    src_dir="${TCDIST_DIR}/br_admin"
    echo -e "\e[30;107mGenerating qcow2 image for avocado-vt use\e[0m"
    virt-make-fs --format=qcow2 "${image_dir}/rootfs.tar" "${image_dir}/CustomLinux.qcow2"
    virt-copy-in -a "${image_dir}/CustomLinux.qcow2" "${src_dir}/br2-ext/avocado-vt/cfg/interfaces" /etc/network
    virt-copy-in -a "${image_dir}/CustomLinux.qcow2" "${src_dir}"/br2-ext/avocado-vt/guest-tools/* /usr/bin/
    virt-edit -a "${image_dir}/CustomLinux.qcow2" /etc/ssh/sshd_config -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/'
    e2mkdir "${2}:/var/lib/avocado/data/avocado-vt/"
    echo -e "\e[30;107mCopying avocado-vt bootstrap to rootfs\e[0m"
    find /var/lib/avocado/data/avocado-vt -exec e2cp {} "${2}":{} \;
    e2cp -p "${src_dir}"/br2-ext/avocado-vt/host-tools/*.sh "${2}:/root/"
    e2cp -p "${src_dir}"/br2-ext/avocado-vt/host-tools/kvm "${2}:/usr/bin/"
    e2cp "${src_dir}"/br2-ext/avocado-vt/cfg/qemu-base.cfg "${2}:/var/lib/avocado/data/avocado-vt/backends/qemu/cfg/base.cfg"
    e2cp "${image_dir}/CustomLinux.qcow2" "${2}:/var/lib/avocado/data/avocado-vt/images/"
    e2cp "${image_dir}/${TCDIST_KERNEL_IMAGE_FILE}" "${2}:/root/Image"
    set +x
fi

if [ "${TCDIST_ARCH}_${TCDIST_PLATFORM}" == "arm64_ls1012afrwy" ]; then
    set -x
    e2cp -P 644 -O 0 -G 0 "${TCDIST_DIR}"/configs/linux/firmware/ppfe* "${2}:/lib/firmware/"
    set +x
fi
