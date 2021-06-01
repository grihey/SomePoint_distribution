vm_name = br_conn
vm_product = ${TCDIST_ARCH}_${TCDIST_PLATFORM}
vm_buildroot_config = buildroot_config_${TCDIST_ARCH}_kvm
vm_kernel_config = $(vm_product)_kvm_guest_release
vm_kernel_defconfig = $(vm_kernel_config)_defconfig
vm_output = $(vm_name)_$(vm_product)

include ../generic_br_makefile.mk
