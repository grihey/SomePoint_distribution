#!/bin/bash

# Include generic rootfs adjustments (Will load vm specific options too)
. ../adjust_rootfs.sh -hostname -interfaces -ssh "$@"
