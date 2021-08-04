# Add extra files to the list, so size requirements can be calculated on main level
TCDIST_VM_FILES+=$(TCDIST_DIR)/br_admin/vmctl.sh

# Copy extra files to main image
br_admin.files:
	e2cp -P 755 -O 0 -G 0 "$(TCDIST_DIR)/br_admin/vmctl.sh" "$(MAINIMAGE):$(MAINIMAGEDIR)"
