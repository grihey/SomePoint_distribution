ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

VM_NAME:=br_admin
VM_PRODUCT:=$(TCDIST_ARCH)_$(TCDIST_PLATFORM)
VM_BUILDROOT_CONFIG:=buildroot_config_$(TCDIST_ARCH)_kvm
VM_KERNEL_CONFIG:=$(VM_PRODUCT)_kvm_release
VM_KERNEL_DEFCONFIG:=$(VM_KERNEL_CONFIG)_defconfig
VM_OUTPUT:=$(VM_NAME)_$(VM_PRODUCT)

include $(TCDIST_DIR)/generic_br_makefile.mk
