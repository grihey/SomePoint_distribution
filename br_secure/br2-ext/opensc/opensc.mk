################################################################################
#
# opensc
#
################################################################################

OPENSC_VERSION = 0.22.0
OPENSC_SITE = $(call github,OpenSC,OpenSC,$(OPENSC_VERSION))
OPENSC_LICENSE = GPL-2
OPENSC_LICENSE_FILES = LICENSE
OPENSC_DEPENDENCIES = openssl pcsc-lite
OPENSC_AUTORECONF = YES
OPENSC_INSTALL_TARGET = YES

$(eval $(autotools-package))
