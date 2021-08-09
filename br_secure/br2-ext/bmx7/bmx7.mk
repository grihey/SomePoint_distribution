################################################################################
#
# bmx7
#
################################################################################

BMX7_VERSION = master
BMX7_SITE = $(call github,bmx-routing,bmx7,$(BMX7_VERSION))
BMX7_LICENSE = GPL-2
BMX7_LICENSE_FILES = LICENSE
BMX7_DEPENDENCIES = libiw-hp zlib mbedtls

define BMX7_BUILD_CMDS
	(cd $(@D); \
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/$(d)/src CC="$(TARGET_CC)")
endef

define BMX7_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/src/bmx7 $(TARGET_DIR)/usr/bin/bmx7
endef

$(eval $(generic-package))
