################################################################################
#
# avocado-framework
#
################################################################################

AVOCADO_VERSION = 85.0
AVOCADO_SOURCE = avocado-framework-$(AVOCADO_VERSION).tar.gz
AVOCADO_SITE = https://files.pythonhosted.org/packages/34/ba/ad973f64bc3dbef9327fbe46366b507888a670aea84084fc495c38c28d14
AVOCADO_SETUP_TYPE = setuptools
AVOCADO_LICENSE = Apache-2.0
AVOCADO_LICENSE_FILES = LICENSE

$(eval $(python-package))
