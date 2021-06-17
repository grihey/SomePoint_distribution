ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

OFIX=$(TCDIST_OUTPUT)/$(vm_name)
LFIX=$(OFIX)/output_$(vm_product)
IFIX=$(TCDIST_DIR)/$(vm_name)

all: $(OFIX)/$(vm_output).ext2 $(OFIX)/$(vm_output).$(TCDIST_KERNEL_IMAGE_FILE)

config: $(LFIX)/.config $(OFIX)/$(vm_kernel_defconfig)

clean:
	if [ -d "$(LFIX)" ]; then make "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot" clean; fi
	rm -rf "$(OFIX)/$(vm_kernel_defconfig)" \
        "$(LFIX)/.config" \
        "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm" \
        "$(OFIX)/$(vm_output).ext2" \
        "$(OFIX)/$(vm_output).$(TCDIST_KERNEL_IMAGE_FILE)"

menuconfig:
	make "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot" menuconfig

linux-menuconfig:
	make "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot" linux-menuconfig

linux-rebuild:
	make "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot" linux-rebuild

distclean:
	rm -rf "$(OFIX)"/output_* "$(OFIX)/$(vm_kernel_defconfig)" "$(OFIX)"/generated_buildroot_config_*

image:
	@echo This target would get the latest working image from artifactory without building anything
	@echo If it was implemented
	@exit 255

$(OFIX)/$(vm_output).ext2: $(LFIX)/images/rootfs.ext2 $(IFIX)/$(vm_name)_config.sh $(TCDIST_DIR)/adjust_rootfs.sh
	"$(TCDIST_DIR)/adjust_rootfs.sh" "$(LFIX)/images/rootfs.ext2" "$(OFIX)/$(vm_output).ext2"

$(OFIX)/$(vm_output).$(TCDIST_KERNEL_IMAGE_FILE): $(LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)
	cp -f "$(LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)" "$(OFIX)/$(vm_output).$(TCDIST_KERNEL_IMAGE_FILE)"

$(LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE): $(LFIX)/images/rootfs.ext2

$(LFIX)/images/rootfs.ext2: $(LFIX)/.config $(OFIX)/$(vm_kernel_defconfig)
	make BR2_EXTERNAL=$(IFIX)/br2-ext "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot"

$(LFIX)/.config: $(IFIX)/$(vm_buildroot_config)
	mkdir -p $(LFIX)
	cp -f "$(IFIX)/$(vm_buildroot_config)" "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm"
	if [ -f "$(IFIX)/buildroot_config_$(vm_product)_kvm_fragment" ]; then \
        cat "$(IFIX)/buildroot_config_$(vm_product)_kvm_fragment" >> "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm"; \
    fi
ifeq ($(TCDIST_SYS_TEST),1)
	if [ -f "$(IFIX)/buildroot_config_$(vm_product)_systest_fragment" ] ; then \
        cat "$(IFIX)/buildroot_config_$(vm_product)_systest_fragment" >> "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm"; \
	fi
endif
	sed -i 's/TC_BR_VM_BUILDROOT_DEFCONFIG/$(vm_name)\/buildroot_config_$(vm_product)_kvm/' "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm"
	sed -i 's/TC_BR_VM_KERNEL_DEFCONFIG/$(vm_name)\/$(vm_kernel_defconfig)/' "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm"
	cp -f "$(OFIX)/generated_buildroot_config_$(vm_product)_kvm" "$(LFIX)/.config"
	make BR2_EXTERNAL=$(IFIX)/br2-ext "O=$(LFIX)" -C "$(TCDIST_DIR)/buildroot" olddefconfig

# Related config fragments from ${TCDIST_DIR}/configs/linux/ could be added as dependency
# But for now, if you change the fragments, then remove $(vm_kernel_defconfig)
$(OFIX)/$(vm_kernel_defconfig):
	"$(TCDIST_DIR)/configs/linux/defconfig_builder.sh" -t "$(vm_kernel_config)" -k "$(TCDIST_DIR)/linux" -o "$(OFIX)"
ifeq ("$(TCDIST_SUB_ARCH)","amd")
	sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "$(OFIX)/$(vm_kernel_defconfig)"
endif

.PHONY: all clean distclean config image menuconfig linux-rebuild linux-menuconfig
