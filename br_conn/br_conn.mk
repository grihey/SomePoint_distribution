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
