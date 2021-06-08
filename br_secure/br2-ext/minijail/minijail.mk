################################################################################
#
# minijail
#
################################################################################

MINIJAIL_VERSION = linux-v16
MINIJAIL_SITE = $(call github,google,minijail,$(MINIJAIL_VERSION))
MINIJAIL_LICENSE = BSD-Style
MINIJAIL_LICENSE_FILES = LICENSE

define MINIJAIL_BUILD_CMDS
	(cd $(@D); \
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/$(d) CC="$(TARGET_CC)")
endef

define MINIJAIL_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/minijail0 \
		$(TARGET_DIR)/usr/bin/minijail0
	$(INSTALL) -m 0755 -D $(@D)/libminijailpreload.so \
		$(TARGET_DIR)/lib/libminijailpreload.so
	$(INSTALL) -m 0755 -D $(@D)/libminijail.so \
		$(TARGET_DIR)/lib/libminijail.so
endef

$(eval $(generic-package))
