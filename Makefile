ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

SHELL=/bin/bash

all: $(TCDIST_OUTPUT)/.tcdist.macs

# Just include generated makefile from output dir
include $(TCDIST_OUTPUT)/Makefile.def

$(TCDIST_OUTPUT)/.tcdist.macs:
	./genmacs.sh > $@
