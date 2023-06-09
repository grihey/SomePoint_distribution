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
        "$(VM_LFIX)/selinux" \
        "$(VM_LFIX)/.brsourced" \
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

$(VM_PREFIX)sdk:
	make "BR2_EXTERNAL=$(VM_IFIX)/br2-ext" "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" sdk

$(VM_PREFIX)distclean:
	rm -rf "$(VM_OFIX)"/output_* "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)" "$(VM_OFIX)"/generated_buildroot_config_*

$(VM_PREFIX)image:
	@echo This target would get the latest working image from artifactory without building anything
	@echo If it was implemented
	@exit 255

$(VM_PREFIX)selinux:
	rm -rf "$(VM_LFIX)/selinux"
	mkdir -p "$(VM_LFIX)/selinux"
	cp -af "$(TCDIST_DIR)/selinux" "$(VM_LFIX)"
	cp -rf "$(VM_IFIX)/selinux" "$(VM_LFIX)"

$(VM_OFIX)/$(VM_OUTPUT).ext2: $(VM_LFIX)/images/rootfs.ext2 $(VM_IFIX)/$(VM_NAME)_config.sh
	"$(VM_IFIX)/adjust_rootfs.sh" "$(VM_LFIX)/images/rootfs.ext2" "$(VM_OFIX)/$(VM_OUTPUT).ext2"

$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE): $(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)
	cp -f "$(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE)" "$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_KERNEL_IMAGE_FILE)"

$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_DEVTREE): $(VM_LFIX)/images/$(TCDIST_DEVTREE)
	cp -f "$(VM_LFIX)/images/$(TCDIST_DEVTREE)" "$(VM_OFIX)/$(VM_OUTPUT).$(TCDIST_DEVTREE)"

$(VM_LFIX)/images/$(TCDIST_KERNEL_IMAGE_FILE): $(VM_LFIX)/images/rootfs.ext2

$(VM_LFIX)/.brsourced: $(VM_LFIX)/.config
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" source
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" linux-extract
	touch $(VM_LFIX)/.brsourced

$(VM_LFIX)/images/rootfs.ext2: $(VM_PREFIX)selinux $(VM_LFIX)/.config $(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot"
	make BR2_EXTERNAL=$(VM_IFIX)/br2-ext "O=$(VM_LFIX)" -C "$(TCDIST_DIR)/buildroot" ccache-stats > $(VM_LFIX)/ccache-stats.txt

# All the targets don't have fragments so use wildcard buildroot_*_fragment
$(VM_LFIX)/.config: $(VM_IFIX)/$(VM_BUILDROOT_CONFIG) $(wildcard $(VM_IFIX)/buildroot_*_fragment)
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

# Kernel defconfig will be regenerated if any of kernel config fragments has changed (even if the changed one is not used in this setup)
$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG): $(VM_LFIX)/.brsourced $(wildcard $(TCDIST_DIR)/configs/linux/*.cfg) $(wildcard $(TCDIST_DIR)/configs/linux/*_map.txt)
	source <(grep BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION $(VM_LFIX)/.config); \
    "$(TCDIST_DIR)/scripts/defconfig_builder.sh" -t "$(VM_KERNEL_CONFIG)" -k "$(VM_LFIX)/build/linux-$$$${BR2_LINUX_KERNEL_CUSTOM_REPO_VERSION}" \
        -f $(TCDIST_DIR)/scripts/fragments -m $(TCDIST_DIR)/scripts/maps -o "$(VM_OFIX)"
	mv -f $(VM_OFIX)/$(VM_KERNEL_DEFCONFIG) $(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)
ifeq ("$(TCDIST_SUB_ARCH)","amd")
	sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)"
else
	sed -i 's/CONFIG_KVM_AMD=y/CONFIG_KVM_INTEL=y/' "$(VM_OFIX)/generated_$(VM_KERNEL_DEFCONFIG)"
endif

$(VM_NAME): $(VM_PREFIX)all

ifeq ($(TCDIST_PLATFORM),qemu)
$(VM_PREFIX)all: $(VM_OFIX)/$(VM_NAME).mac
endif

.PHONY: $(VM_PREFIX)all $(VM_PREFIX)clean $(VM_PREFIX)distclean $(VM_PREFIX)config $(VM_PREFIX)image $(VM_PREFIX)menuconfig \
        $(VM_PREFIX)selinux $(VM_PREFIX)linux-rebuild $(VM_PREFIX)linux-menuconfig $(VM_NAME)

endef # Generic_br_makefile

# Eval will cause all variables in above targets and recipes to be expanded on the first pass, which is necessary for
# these recipes to work.
$(eval $(call Generic_br_makefile))
