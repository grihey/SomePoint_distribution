################################################################################
#
# alfred
#
################################################################################

ALFRED_VERSION = 2021.1
#https://github.com/open-mesh-mirror/alfred/archive/refs/tags/v2021.1.tar.gz
#https://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-2021.1.tar.gz
ALFRED_SOURCE = alfred-$(ALFRED_VERSION).tar.gz
ALFRED_SITE = https://downloads.open-mesh.org/batman/stable/sources/alfred
ALFRED_LICENSE = GPL-2
ALFRED_LICENSE_FILES = LICENSE

define ALFRED_BUILD_CMDS
	(cd $(@D); \
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/$(d) CC="$(TARGET_CC)")
endef

define ALFRED_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/alfred \
		$(TARGET_DIR)/usr/bin/alfred
	$(INSTALL) -m 0755 -D $(@D)/vis/batadv-vis \
		$(TARGET_DIR)/usr/bin/batadv-vis
endef

$(eval $(generic-package))
