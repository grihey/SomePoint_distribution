ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

SHELL:=/bin/bash
MFLAGS:=
MAINIMAGEDIR:=/root
MAINIMAGE:=$(TCDIST_OUTPUT)/$(TCDIST_NAME)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
MAINKERNEL:=$(TCDIST_OUTPUT)/$(TCDIST_NAME)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)

ADMINIMAGE:=$(TCDIST_OUTPUT)/$(TCDIST_ADMIN)/$(TCDIST_ADMIN)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
ADMINKERNEL:=$(TCDIST_OUTPUT)/$(TCDIST_ADMIN)/$(TCDIST_ADMIN)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)

VMFILETARGETS:=$(addsuffix .files,$(TCDIST_VMLIST))
CLEANTARGETS:=$(addsuffix .clean,$(TCDIST_VMLIST))
DISTCLEANTARGETS:=$(addsuffix .distclean,$(TCDIST_VMLIST))

# Get list of all vm files
TCDIST_VM_FILES:=
include $(foreach vm,$(TCDIST_VMLIST),$(vm)/$(vm).mk)

all: $(TCDIST_OUTPUT)/.tcdist.macs $(MAINIMAGE) $(MAINKERNEL)

copyandresize:
	cp -f $(ADMINIMAGE) $(MAINIMAGE)
	resize2fs $(MAINIMAGE) $(shell ./size_calc.sh $(ADMINIMAGE) $(TCDIST_VM_FILES))

ifeq ($(TCDIST_PLATFORM),qemu)
$(MAINIMAGE): $(TCDIST_OUTPUT)/.tcdist.macs
endif

$(MAINIMAGE): $(TCDIST_VMLIST) copyandresize $(VMFILETARGETS)

$(MAINKERNEL): $(TCDIST_VMLIST)
	cp -f $(ADMINKERNEL) $@

$(TCDIST_OUTPUT)/.tcdist.macs:
	./genmacs.sh > $@

$(TCDIST_VMLIST):
	make $(MFLAGS) -C $@ all

$(CLEANTARGETS):
	make $(MFLAGS) -C $(basename $@) clean

$(DISTCLEANTARGETS):
	make $(MFLAGS) -C $(basename $@) distclean

clean: $(CLEANTARGETS)
	rm -rf $(TCDIST_OUTPUT)/*.ext2 $(TCDIST_OUTPUT)/*Image

distclean: clean $(DISTCLEANTARGETS)
	rm -rf $(TCDIST_OUTPUT)/.setup_sh_config $(TCDIST_OUTPUT)/.tcdist_macs

.PHONY: all copyandresize clean distclean $(TCDIST_VMLIST) $(CLEANTARGETS) $(DISTCLEANTARGETS)
