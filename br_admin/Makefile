ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

SHELL:=/bin/bash

VM_NAME:=br_admin
VM_PRODUCT:=$(TCDIST_ARCH)_$(TCDIST_PLATFORM)
VM_BUILDROOT_CONFIG:=buildroot_config_$(TCDIST_ARCH)_kvm
VM_KERNEL_CONFIG:=$(VM_PRODUCT)_kvm_release
VM_KERNEL_DEFCONFIG:=$(VM_KERNEL_CONFIG)_defconfig
VM_OUTPUT:=$(VM_NAME)_$(VM_PRODUCT)

include $(TCDIST_DIR)/generic_br_makefile.mk

# Add extra files to the list, so size requirements can be calculated on main level
TCDIST_VM_FILES+=$(TCDIST_DIR)/br_admin/vmctl.sh

# Copy extra files to main image
br_admin.files:
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_DIR)/br_admin/vmctl.sh" "$(MAINIMAGE):$(MAINIMAGEDIR)"

$(VM_OFIX)/br_admin.mac: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 1st line from macs file, 1st is admin, 2nd and 3rd are for conn vm, 4th is for secure os
	sed "1q;d" $< > $@
