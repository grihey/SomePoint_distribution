################################################################################
#
# avocado-vt
#
################################################################################

AVOCADO_VT_VERSION = 85.0
AVOCADO_VT_SOURCE = avocado-framework-plugin-vt-$(AVOCADO_VT_VERSION).tar.gz
AVOCADO_VT_SITE = https://files.pythonhosted.org/packages/66/7e/42fea1466ff2fd881c877286293e8b2e0e646048cf01e1e82d80e158aac7
AVOCADO_VT_SETUP_TYPE = setuptools
AVOCADO_VT_LICENSE = Apache-2.0
AVOCADO_VT_LICENSE_FILES = LICENSE

$(eval $(python-package))
