# Add extra files to the list, so size requirements can be calculated on main level
TCDIST_VM_FILES+=$(TCDIST_DIR)/br_secure/vm_2.sh
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)
TCDIST_VM_FILES+=$(TCDIST_OUTPUT)/br_secure/br_secure.mac

# Copy extra files to main image
br_secure.files:
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_DIR)/br_secure/vm_2.sh" "$(MAINIMAGE):$(MAINIMAGEDIR)"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2" "$(MAINIMAGE):$(MAINIMAGEDIR)/br_secure.ext2"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_secure/br_secure_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)" "$(MAINIMAGE):$(MAINIMAGEDIR)/br_secure.$(TCDIST_KERNEL_IMAGE_FILE)"
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_OUTPUT)/br_secure/br_secure.mac" "$(MAINIMAGE):$(MAINIMAGEDIR)"
