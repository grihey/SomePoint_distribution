vm_name = br_secure
vm_product = ${TCDIST_ARCH}_${TCDIST_PLATFORM}
vm_buildroot_config = buildroot_config_${TCDIST_ARCH}_kvm_secure
vm_kernel_config = $(vm_product)_kvm_guest_secure_release
vm_kernel_defconfig = $(vm_kernel_config)_defconfig
vm_output = $(vm_name)_$(vm_product)

include ../generic_br_makefile.mk
