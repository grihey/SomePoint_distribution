#!/bin/bash

export TCDIST_VM_NAME="br_conn"

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Include generic rootfs adjustment functions
# Disable shellcheck warning about variable source name
# shellcheck disable=SC1090
. "${SDIR}/../adjust_rootfs.sh" "$1"

Arfs_load_config
# Variable purposefully unquoted, it contains list of space separated options
# shellcheck disable=SC2086
Arfs_apply ${ARFS_OPTIONS} "$@"

# Insert vm specific adjustments here
