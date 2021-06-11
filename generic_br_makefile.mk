# vm_name = br_my_awesome_vm
# vm_buildroot_config = buildroot_config_${TCDIST_ARCH}_kvm_secure

all: $(vm_output).ext2 $(vm_output).${TCDIST_KERNEL_IMAGE_FILE}

config: output_$(vm_product)/.config $(vm_kernel_defconfig)

clean:
	if [ -d output_$(vm_product) ]; then make "O=${PWD}/output_$(vm_product)" -C ../buildroot clean; fi
	rm -rf $(vm_kernel_defconfig) \
		output_$(vm_product)/.config \
		generated_buildroot_config_$(vm_product)_kvm \
		$(vm_output).ext2 \
		$(vm_output).${TCDIST_KERNEL_IMAGE_FILE}

menuconfig:
	make O=${PWD}/output_$(vm_product) -C ../buildroot menuconfig

linux-menuconfig:
	make O=${PWD}/output_$(vm_product) -C ../buildroot linux-menuconfig

linux-rebuild:
	make O=${PWD}/output_$(vm_product) -C ../buildroot linux-rebuild

distclean:
	rm -rf output_* $(vm_kernel_defconfig) generated_buildroot_config_*

image:
	@echo This target would get the latest working image from artifactory without building anything
	@echo If it was implemented
	@exit 255

$(vm_output).ext2: output_$(vm_product)/images/rootfs.ext2 $(vm_name)_config.sh ../adjust_rootfs.sh
	./adjust_rootfs.sh output_$(vm_product)/images/rootfs.ext2 $(vm_output).ext2

$(vm_output).${TCDIST_KERNEL_IMAGE_FILE}: output_$(vm_product)/images/${TCDIST_KERNEL_IMAGE_FILE} output_$(vm_product)/images/${TCDIST_DEVTREE}
	cp -f output_$(vm_product)/images/${TCDIST_KERNEL_IMAGE_FILE} ./$(vm_output).${TCDIST_KERNEL_IMAGE_FILE}
ifeq ("${TCDIST_ARCH}","arm64")
	cp -f output_$(vm_product)/images/${TCDIST_DEVTREE} ./$(vm_output).${TCDIST_DEVTREE}
endif

output_$(vm_product)/images/${TCDIST_KERNEL_IMAGE_FILE}: output_$(vm_product)/images/rootfs.ext2

output_$(vm_product)/images/rootfs.ext2: output_$(vm_product)/.config $(vm_kernel_defconfig)
	@# Check if br_*/br2-ext directory exists, if it does, setup
	@# EXT makefile variable to "BR2_EXTERNAL=br_*/br2-ext". This
	@# will be passed to buildroot make to build the external
	@# packages
	$(eval EXT := $(shell if [ -d ${PWD}/br2-ext ] ; then \
		echo "BR2_EXTERNAL=${PWD}/br2-ext"; fi ))
	make $(EXT) O=${PWD}/output_$(vm_product) -C ../buildroot

output_$(vm_product)/.config: $(vm_buildroot_config)
	mkdir -p output_$(vm_product)
	cat $(vm_buildroot_config) > generated_buildroot_config_$(vm_product)_kvm
	if [ -f buildroot_config_$(vm_product)_kvm_fragment ]; then \
		cat buildroot_config_$(vm_product)_kvm_fragment >> generated_buildroot_config_$(vm_product)_kvm; \
	fi
	sed -i 's/TC_BR_VM_BUILDROOT_DEFCONFIG/$(vm_name)\/buildroot_config_$(vm_product)_kvm/' generated_buildroot_config_$(vm_product)_kvm
	sed -i 's/TC_BR_VM_KERNEL_DEFCONFIG/$(vm_name)\/$(vm_kernel_defconfig)/' generated_buildroot_config_$(vm_product)_kvm
	cp -f generated_buildroot_config_$(vm_product)_kvm output_$(vm_product)/.config

# Related config fragments from ${TCDIST_DIR}/configs/linux/ could be added as dependency
# But for now, if you change the fragments, then remove $(vm_kernel_defconfig)
$(vm_kernel_defconfig):
	"${TCDIST_DIR}/configs/linux/defconfig_builder.sh" -t "$(vm_kernel_config)" -k "${TCDIST_DIR}/linux" -o .
ifeq ("${TCDIST_SUB_ARCH}","amd")
	sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' $(vm_kernel_defconfig)
endif

.PHONY: all clean distclean config image menuconfig linux-rebuild linux-menuconfig
