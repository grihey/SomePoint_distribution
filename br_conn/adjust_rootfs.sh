#!/bin/bash

TCDIST_VM_NAME="br_conn"

# Include generic rootfs adjustment functions
. ${TCDIST_DIR}/adjust_rootfs.sh "$1"

Arfs_load_config
# Variable purposefully unquoted, it contains list of space separated options
# shellcheck disable=SC2086
Arfs_apply ${ARFS_OPTIONS} "$@"

# Insert vm specific adjustments here
