################################################################################
#
# libiw-hp
#
################################################################################

LIBIW_HP_VERSION = master
LIBIW_HP_SITE = $(call github,HewlettPackard,wireless-tools,$(LIBIW_HP_VERSION))
LIBIW_HP_INSTALL_STAGING = YES
LIBIW_HP_LICENSE = GPL-2
LIBIW_HP_LICENSE_FILES = LICENSE

define LIBIW_HP_BUILD_CMDS
	(cd $(@D); \
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/$(d)/wireless_tools CC="$(TARGET_CC)")
endef

define LIBIW_HP_INSTALL_STAGING_CMDS
	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/libiw-hp.so.29 $(STAGING_DIR)/usr/lib/libiw-hp.so.29
	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwlib.h $(STAGING_DIR)/usr/include/iwlib.h
	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/wireless.h $(STAGING_DIR)/usr/include/wireless.h
endef

define LIBIW_HP_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/libiw-hp.so.29 $(STAGING_DIR)/usr/lib/libiw-hp.so.29
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/ifrename $(STAGING_DIR)/usr/bin/ifrename
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwevent $(STAGING_DIR)/usr/bin/iwevent
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwgetid $(STAGING_DIR)/usr/bin/iwgetid
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwspy $(STAGING_DIR)/usr/bin/iwspy
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwpriv $(STAGING_DIR)/usr/bin/iwpriv
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwlist $(STAGING_DIR)/usr/bin/iwlist
#	$(INSTALL) -m 0755 -D $(@D)/wireless_tools/iwconfig $(STAGING_DIR)/usr/bin/iwconfig
endef

$(eval $(generic-package))
