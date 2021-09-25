IMX_MKIMAGE_PATH:=$(VM_LFIX)/imx-mkimage
IMX_MKIMAGE_SOC_PATH:=$(IMX_MKIMAGE_PATH)/iMX8QX

TCDIST_IMXBL_PRIMARY_LIST += $(if $(TCDIST_BL_TEE), tee.bin, )

IMXBL_SRC_PRIMARY_PATHS := $(addprefix $(VM_LFIX)/images/,$(TCDIST_IMXBL_PRIMARY_LIST))
IMXBL_SRC_SECO_PATH := $(VM_LFIX)/images/$(TCDIST_IMXBL_SECO_COMP)
IMXBL_SRC_SCFW_PATH := $(VM_LFIX)/images/$(TCDIST_IMXBL_SCFW_COMP)

IMXBL_TARGET_PRIMARY_PATHS := $(addprefix $(IMX_MKIMAGE_PATH)/iMX8QX/,$(TCDIST_IMXBL_PRIMARY_LIST))
IMXBL_TARGET_SECO_PATH := $(IMX_MKIMAGE_SOC_PATH)/mx8qxc0-ahab-container.img
IMXBL_TARGET_SCFW_PATH := $(IMX_MKIMAGE_SOC_PATH)/scfw_tcm.bin

$(VM_PREFIX)all: $(if $(TCDIST_BL),$(TCDIST_OUTPUT)/$(TCDIST_BL),)

# imx-mkimage repo makefile use $(PWD) to define folder of itself. hence calling make leads to occurance of
# building artefacts in current directory instead of imx-mkimage. that the reason why additional mv command
# is using.
$(TCDIST_OUTPUT)/$(TCDIST_BL): imx-mkimage $(IMXBL_TARGET_PRIMARY_PATHS) $(IMXBL_TARGET_SECO_PATH) $(IMXBL_TARGET_SCFW_PATH)
	make -C $(IMX_MKIMAGE_PATH) all
	mv $(shell pwd)/mkimage_imx8 $(IMX_MKIMAGE_PATH)
	make -C $(IMX_MKIMAGE_PATH) REV=C0 SOC=iMX8QX flash
	cp $(IMX_MKIMAGE_PATH)/iMX8QX/flash.bin $@

$(IMXBL_TARGET_PRIMARY_PATHS): $(IMXBL_SRC_PRIMARY_PATHS)
	cp $^ $(shell dirname $@)

$(IMXBL_TARGET_SECO_PATH): $(IMXBL_SRC_SECO_PATH)
	cp $^ $@

$(IMXBL_TARGET_SCFW_PATH): $(IMXBL_SRC_SCFW_PATH)
	cp $^ $@

imx-mkimage: imx-mkimage.folder
	git clone -b ${TCDIST_IMX_MKIMAGE_GIT_BRANCH} ${TCDIST_IMX_MKIMAGE_GIT_URL} $(IMX_MKIMAGE_PATH)

imx-mkimage.folder:
	rm -rf $(IMX_MKIMAGE_PATH)
	mkdir -p $(IMX_MKIMAGE_PATH)
