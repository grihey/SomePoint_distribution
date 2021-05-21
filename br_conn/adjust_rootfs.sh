#!/bin/bash

# Include generic rootfs adjustments
. ../adjust_rootfs.sh -hostname -interfaces "$@"

# Insert vm specific adjustments here
