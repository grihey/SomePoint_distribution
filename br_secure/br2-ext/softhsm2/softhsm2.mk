################################################################################
#
# softhsm2
#
################################################################################

SOFTHSM2_VERSION = 2.6.1
SOFTHSM2_SITE = $(call github,opendnssec,SoftHSMv2,$(SOFTHSM2_VERSION))
SOFTHSM2_LICENSE = GPL-2
SOFTHSM2_LICENSE_FILES = LICENSE
SOFTHSM2_DEPENDENCIES = libtool openssl
SOFTHSM2_AUTORECONF = YES
SOFTHSM2_INSTALL_TARGET = YES

$(eval $(autotools-package))
