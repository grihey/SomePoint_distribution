# Set prefix only if make is run in main level
ifdef MAINIMAGE
VM_PREFIX:=$(VM_NAME).
else
VM_PREFIX:=
endif

VM_OFIX:=$(TCDIST_OUTPUT)/$(VM_NAME)
VM_LFIX:=$(VM_OFIX)/output_$(VM_PRODUCT)
VM_IFIX:=$(TCDIST_DIR)/$(VM_NAME)

# Put all targets into a function so we can evaluate them
define Generic_br_makefile

$(VM_PREFIX)all: $(VM_OFIX)/$(VM_OUTPUT).ext2 $(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE) $(if $(TCDIST_DEVTREE), $(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_DEVTREE), )

$(VM_PREFIX)config: $(VM_LFIX)/.config $(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)

$(VM_PREFIX)clean:
	if [ -d "$(VM_LFIX)" ]; then make "BR2_EXTERNAL=$(VM_IFIX)/br2-ext" "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" clean; fi
	rm -rf "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)" \
        "$(VM_LFIX)/.config" \
        "$(VM_LFIX)/ccache-stats.txt" \
        "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm" \
        "$(VM_OFIX)/$(VM_OUTPUT).ext2" \
        "$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE)"

$(VM_PREFIX)menuconfig:
	make "BR2_EXTERNAL=$(VM_IFIX)/br2-ext" "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" menuconfig

$(VM_PREFIX)linux-menuconfig:
	make "BR2_EXTERNAL=$(VM_IFIX)/br2-ext" "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" linux-menuconfig

$(VM_PREFIX)linux-rebuild:
	make "BR2_EXTERNAL=$(VM_IFIX)/br2-ext" "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" linux-rebuild

$(VM_PREFIX)distclean:
	rm -rf "$(VM_OFIX)"/output_* "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)" "$(VM_OFIX)"/generated_buildroot_config_*

$(VM_PREFIX)image:
	@echo This target would get the latest working image from artifactory without building anything
	@echo If it was implemented
	@exit 255

$(VM_OFIX)/$(VM_OUTPUT).ext2: $(VM_LFIX)/images/rootfs.ext2 $(VM_IFIX)/$(VM_NAME)_config.sh
	"$(VM_IFIX)/adjust_rootfs.sh" "$(VM_LFIX)/images/rootfs.ext2" "$(VM_OFIX)/$(VM_OUTPUT).ext2"

$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE): $(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)
	cp -f "$(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)" "$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE)"

$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_DEVTREE): $(VM_LFIX)/images/$(TCDIST_DEVTREE)
	cp -f "$(VM_LFIX)/images/$(TCDIST_DEVTREE)" "$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_DEVTREE)"

$(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE): $(VM_LFIX)/images/rootfs.ext2

$(VM_LFIX)/images/rootfs.ext2: $(VM_LFIX)/.config $(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" source
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot"
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" ccache-stats > $(VM_LFIX)/ccache-stats.txt

$(VM_LFIX)/.config: $(VM_IFIX)/$(VM_BUILDROOT_CONFIG)
	mkdir -p $(VM_LFIX)
	cp -f "$(VM_IFIX)/$(VM_BUILDROOT_CONFIG)" "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm"
	if [ -f "$(VM_IFIX)/buildroot_config_$(VM_PRODUCT)_kvm_fragment" ]; then \
        cat "$(VM_IFIX)/buildroot_config_$(VM_PRODUCT)_kvm_fragment" >> "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm"; \
    fi
ifeq ($(TCDIST_SYS_TEST),1)
	if [ -f "$(VM_IFIX)/buildroot_config_$(VM_PRODUCT)_systest_fragment" ] ; then \
        cat "$(VM_IFIX)/buildroot_config_$(VM_PRODUCT)_systest_fragment" >> "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm"; \
    fi
endif
	sed -i 's/TC_BR_VM_BUILDROOT_DEFCONFIG/$(VM_NAME)\/buildroot_config_$(VM_PRODUCT)_kvm/' "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm"
	sed -i 's/TC_BR_VM_KERNEL_DEFCONFIG/$(VM_NAME)\/generated_$(VM_KERNEL_DEFCONFIG)/' "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm"
	cp -f "$(VM_OFIX)/generated_buildroot_config_$(VM_PRODUCT)_kvm" "$(VM_LFIX)/.config"
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" olddefconfig

$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG): $(VM_IFIX)/$(VM_KERNEL_DEFCONFIG)
	cp -f "$(VM_IFIX)/$(VM_KERNEL_DEFCONFIG)" "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)"
ifeq ("$(TCDIST_SUB_ARCH)","amd")
	sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)"
else
	sed -i 's/CONFIG_KVM_AMD=y/CONFIG_KVM_INTEL=y/' "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)"
endif

# Related config fragments from ${TCDIST_DIR}/configs/linux/ could be added as dependency
# But for now, if you change the fragments, then remove $(VM_KERNEL_DEFCONFIG)
$(VM_IFIX)/$(VM_KERNEL_DEFCONFIG):
	"$(TCDIST_DIR)/check_linux_branch.sh"
	"$(TCDIST_DIR)/configs/linux/defconfig_builder.sh" -t "$(VM_KERNEL_CONFIG)" -k "$(TCDIST_DIR)/linux" -o "$(VM_IFIX)"

$(VM_NAME): $(VM_PREFIX)all

ifeq ($(TCDIST_PLATFORM),qemu)
$(VM_PREFIX)all: $(VM_OFIX)/$(VM_NAME).mac
endif

.PHONY: $(VM_PREFIX)all $(VM_PREFIX)clean $(VM_PREFIX)distclean $(VM_PREFIX)config $(VM_PREFIX)image $(VM_PREFIX)menuconfig \
        $(VM_PREFIX)linux-rebuild $(VM_PREFIX)linux-menuconfig $(VM_NAME)

endef # Generic_br_makefile

# Eval will cause all variables in above targets and recipes to be expanded on the first pass, which is necessary for
# these recipes to work.
$(eval $(call Generic_br_makefile))
