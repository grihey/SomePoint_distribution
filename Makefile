ifndef TCDIST_DIR
$(error Environment not set up correctly, please run make via setup.sh)
endif

# Just include generated makefile from output dir
include $(TCDIST_OUTPUT)/Makefile.def
