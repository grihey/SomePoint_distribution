ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

vm_name = br_conn
vm_product = ${TCDIST_ARCH}_${TCDIST_PLATFORM}
vm_buildroot_config = buildroot_config_${TCDIST_ARCH}_kvm
vm_kernel_config = $(vm_product)_kvm_guest_release
vm_kernel_defconfig = $(vm_kernel_config)_defconfig
vm_output = $(vm_name)_$(vm_product)

include ${TCDIST_DIR}/generic_br_makefile.mk

ifeq ($(TCDIST_PLATFORM),qemu)
all: $(OFIX)/br_conn.mac_1 $(OFIX)/br_conn.mac_2
endif

$(OFIX)/br_conn.mac_1: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 2nd line from macs file, 1st is admin, 2nd and 3rd are for conn vm, 4th is for secure os
	sed "2q;d" $< > $@

$(OFIX)/br_conn.mac_2: $(TCDIST_OUTPUT)/.tcdist.macs
#   Get 3rd line from macs file 1st is admin, 2nd and 3rd are for conn vm, 4th is for secure os
	sed "3q;d" $< > $@
