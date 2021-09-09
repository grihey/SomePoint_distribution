ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

SHELL:=/bin/bash

VM_NAME:=br_conn
VM_PRODUCT:=$(TCDIST_ARCH)_$(TCDIST_PLATFORM)
VM_BUILDROOT_CONFIG:=buildroot_config_$(TCDIST_ARCH)_kvm
VM_KERNEL_CONFIG:=$(VM_PRODUCT)_kvm_guest_release
VM_KERNEL_DEFCONFIG:=$(VM_KERNEL_CONFIG)_defconfig
VM_OUTPUT:=$(VM_NAME)_$(VM_PRODUCT)

include $(TCDIST_DIR)/generic_br_makefile.mk

# Add extra files to the list, so size requirements can be calculated on main level
TCDIST_VM_FILES+=$(TCDIST_DIR)/br_conn/vm_1.sh
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_conn/br_conn_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_conn/br_conn_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_conn/br_conn.mac_1
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_conn/br_conn.mac_2

# Copy extra files to main image
br_conn.files:
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_DIR)/br_conn/vm_1.sh" "$(MAINIMAGE):$(MAINIMAGEDIR)"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_conn/br_conn_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2" "$(MAINIMAGE):$(MAINIMAGEDIR)/br_conn.ext2"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_conn/br_conn_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)" "$(MAINIMAGE):$(MAINIMAGEDIR)/br_conn.$(TCDIST_KERNEL_IMAGE_FILE)"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_conn/br_conn.mac_1" "$(MAINIMAGE):$(MAINIMAGEDIR)"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_conn/br_conn.mac_2" "$(MAINIMAGE):$(MAINIMAGEDIR)"

ifeq ($(TCDIST_PLATFORM),qemu)
all: $(VM_OFIX)/br_conn.mac_1 $(VM_OFIX)/br_conn.mac_2
endif

$(VM_OFIX)/br_conn.mac: $(VM_OFIX)/br_conn.mac_1 $(VM_OFIX)/br_conn.mac_2

$(VM_OFIX)/br_conn.mac_1: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 2nd line from macs file, 1st is admin, 2nd and 3rd are for conn vm, 4th is for secure os
	sed "2q;d" $< > $@

$(VM_OFIX)/br_conn.mac_2: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 3rd line from macs file 1st is admin, 2nd and 3rd are for conn vm, 4th is for secure os
	sed "3q;d" $< > $@
