#!/bin/bash

# Include generic rootfs adjustments (Will load vm specific options too)
. ../adjust_rootfs.sh -hostname -interfaces -ssh "$@"

# Insert vm specific adjustments here
set -x
e2cp -P "$TCDIST_ADMIN_MODE" -O "$TCDIST_ADMIN_UID" -G "$TCDIST_ADMIN_UID" vmctl.sh "${2}:${TCDIST_ADMIN_DIR}"
