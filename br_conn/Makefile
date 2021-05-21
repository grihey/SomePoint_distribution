all: br_conn.ext2 br_conn.bzImage

config: output/.config x86_kvm_guest_release_defconfig

clean:
	if [ -d output ]; then make "O=${PWD}/output" -C ../buildroot clean; fi
	rm -rf x86_kvm_guest_release_defconfig output/.config

distclean:
	rm -rf output x86_kvm_guest_release_defconfig

image:
	@echo This target would get the latest working image from artifactory without building anything
	@echo If it was implemented
	@exit 255

br_conn.ext2: output/images/rootfs.ext2 br_conn_config.sh
	./adjust_rootfs.sh output/images/rootfs.ext2 br_conn.ext2

br_conn.bzImage: output/images/bzImage
	cp -f output/images/bzImage ./br_conn.bzImage

output/images/bzImage: output/images/rootfs.ext2

output/images/rootfs.ext2: output/.config x86_kvm_guest_release_defconfig
	make O=${PWD}/output -C ../buildroot

output/.config: buildroot_config_x86_kvm
	mkdir -p output
	cp -f buildroot_config_x86_kvm output/.config

# Related config fragments from ${TCDIST_DIR}/configs/linux/ could be added as dependency
# But for now, if you change the fragments, then remove x86_kvm_release_defconfig
x86_kvm_guest_release_defconfig:
	"${TCDIST_DIR}/configs/linux/defconfig_builder.sh" -t "x86_kvm_guest_release" -k "${TCDIST_DIR}/linux" -o .
ifeq ("${TCDIST_SUB_PLATFORM}","amd")
	sed -i 's/CONFIG_KVM_INTEL=y/CONFIG_KVM_AMD=y/' x86_kvm_release_defconfig
endif

.PHONY: all clean distclean config image
