ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

TCDIST_VM_FILES+=$(TCDIST_DIR)/br_secure/vm_2.sh
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure.macvm_name = br_secure

VM_NAME:=br_secure
VM_PRODUCT:=$(TCDIST_ARCH)_$(TCDIST_PLATFORM)
VM_BUILDROOT_CONFIG:=buildroot_config_$(TCDIST_ARCH)_kvm_secure
VM_KERNEL_CONFIG:=$(VM_PRODUCT)_kvm_guest_secure_release
VM_KERNEL_DEFCONFIG:=$(VM_KERNEL_CONFIG)_defconfig
VM_OUTPUT:=$(VM_NAME)_$(VM_PRODUCT)

include $(TCDIST_DIR)/generic_br_makefile.mk

ifeq ($(TCDIST_PLATFORM),qemu)
all: $(VM_OFIX)/br_secure.mac
endif

$(VM_OFIX)/br_secure.mac: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 4th line from macs file 1st is admin, 2nd and 3rd is for conn vm
	sed "4q;d" $< > $@
