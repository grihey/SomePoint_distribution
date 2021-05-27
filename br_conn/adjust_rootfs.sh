#!/bin/bash

# Include generic rootfs adjustments
. ../adjust_rootfs.sh -hostname -interfaces -ssh "$@"

# Insert vm specific adjustments here
