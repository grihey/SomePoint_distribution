#!/bin/bash

# Include generic rootfs adjustments (Will load vm specific options too)
. ../adjust_rootfs.sh -hostname -interfaces -ssh "$@"

# Insert vm specific adjustments here
set -x
e2cp -P "$TCDIST_ADMIN_MODE" -O "$TCDIST_ADMIN_UID" -G "$TCDIST_ADMIN_UID" vmctl.sh "${2}:${TCDIST_ADMIN_DIR}"

# Copy over any system testing related items
if [ "$TCDIST_SYS_TEST" = "1" ] ; then
    # Uncomment below line to enable virt tools debug
    #export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
    output_dir="${PWD}/output_${TCDIST_ARCH}_${TCDIST_PLATFORM}"
    image_dir="${output_dir}/images"
    echo -e "\e[30;107mGenerating qcow2 image for avocado-vt use\e[0m"
    virt-make-fs --format=qcow2 ${image_dir}/rootfs.tar ${image_dir}/CustomLinux.qcow2
    virt-copy-in -a "${image_dir}/CustomLinux.qcow2" ${PWD}/br2-ext/avocado-vt/cfg/interfaces /etc/network
    virt-copy-in -a "${image_dir}/CustomLinux.qcow2" ${PWD}/br2-ext/avocado-vt/guest-tools/* /usr/bin/
    virt-edit -a "${image_dir}/CustomLinux.qcow2" /etc/ssh/sshd_config -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/'
    e2mkdir "${2}:/var/lib/avocado/data/avocado-vt/"
    echo -e "\e[30;107mCopying avocado-vt bootstrap to rootfs\e[0m"
    find /var/lib/avocado/data/avocado-vt -exec e2cp {} ${2}:{} \;
    e2cp -p br2-ext/avocado-vt/host-tools/*.sh "${2}:/root/"
    e2cp -p br2-ext/avocado-vt/host-tools/kvm "${2}:/usr/bin/"
    e2cp br2-ext/avocado-vt/cfg/qemu-base.cfg "${2}:/var/lib/avocado/data/avocado-vt/backends/qemu/cfg/base.cfg"
    e2cp "${image_dir}/CustomLinux.qcow2" "${2}:/var/lib/avocado/data/avocado-vt/images/"
    e2cp "${image_dir}/${TCDIST_KERNEL_IMAGE_FILE}" "${2}:/root/Image"
fi
