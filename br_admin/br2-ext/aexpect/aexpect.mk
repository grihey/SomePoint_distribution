################################################################################
#
# aexpect
#
################################################################################

AEXPECT_VERSION = 1.6.1
AEXPECT_SOURCE = aexpect-$(AEXPECT_VERSION).tar.gz
AEXPECT_SITE = https://files.pythonhosted.org/packages/70/a8/68e199565972e7a809a656844faddd9fc6cbdbf9eec0cd0b65b4a89a90c5
AEXPECT_SETUP_TYPE = setuptools
AEXPECT_LICENSE = Apache-2.0
AEXPECT_LICENSE_FILES = LICENSE

$(eval $(python-package))
