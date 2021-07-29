ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

SHELL:=/bin/bash
export E2CPFLAGS:=-P 755 -O 0 -G 0
MFLAGS:=
MAINIMAGEDIR:=/root
MAINIMAGE:=$(TCDIST_OUTPUT)/$(TCDIST_NAME)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
MAINKERNEL:=$(TCDIST_OUTPUT)/$(TCDIST_NAME)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)

ADMINIMAGE:=$(TCDIST_OUTPUT)/$(TCDIST_ADMIN)/$(TCDIST_ADMIN)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).ext2
ADMINKERNEL:=$(TCDIST_OUTPUT)/$(TCDIST_ADMIN)/$(TCDIST_ADMIN)_$(TCDIST_ARCH)_$(TCDIST_PLATFORM).$(TCDIST_KERNEL_IMAGE_FILE)

CLEANTARGETS:=$(addsuffix .clean,$(TCDIST_VMLIST))
DISTCLEANTARGETS:=$(addsuffix .distclean,$(TCDIST_VMLIST))

# Get list of all vm files
TCDIST_VM_FILES:=

all: $(TCDIST_OUTPUT)/.tcdist.macs $(MAINIMAGE) $(MAINKERNEL)

$(MAINIMAGE): $(TCDIST_VMLIST)
	cp -f $(ADMINIMAGE) $@
	resize2fs $@ $(shell ./size_calc.sh $(ADMINIMAGE) $(TCDIST_VM_FILES))
	for file in $(TCDIST_VM_FILES); do \
        ./mangle_e2cp.sh $$file $@:$(MAINIMAGEDIR); \
    done

$(MAINKERNEL): $(TCDIST_VMLIST)
	cp -f $(ADMINKERNEL) $@

$(TCDIST_OUTPUT)/.tcdist.macs:
	./genmacs.sh > $@

%/Makefile:
	include $@

$(TCDIST_VMLIST): $(addsuffix /Makefile,$@)
	make $(MFLAGS) -C $@ all

$(CLEANTARGETS):
	make $(MFLAGS) -C $(basename $@) clean

$(DISTCLEANTARGETS):
	make $(MFLAGS) -C $(basename $@) distclean

clean: $(CLEANTARGETS)
	rm -rf $(TCDIST_OUTPUT)/*.ext2 $(TCDIST_OUTPUT)/*Image

distclean: clean $(DISTCLEANTARGETS)
	rm -rf $(TCDIST_OUTPUT)/.setup_sh_config $(TCDIST_OUTPUT)/.tcdist_macs

.PHONY: all clean distclean $(TCDIST_VMLIST) $(CLEANTARGETS) $(DISTCLEANTARGETS)
