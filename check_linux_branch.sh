#!/bin/bash

set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

cd "$SDIR"

. helpers.sh
Load_config

if [ "$1" == "check_script" ]; then
    Shellcheck_bashate check_linux_branch.sh helpers.sh default_setup_sh_config
    exit
fi

cd linux

WANTED_HASH="$(git rev-parse "$TCDIST_LINUX_BRANCH")"
CURRENT_HASH="$(git rev-parse HEAD)"

if [ "$CURRENT_HASH" == "$WANTED_HASH" ]; then
    if git diff-index --quiet HEAD --; then
        echo "Current linux branch seems to be the correct one" >&2
        exit 0
    else
        echo "Current linux branch seems to be the correct one, but it has local changes" >&2
        exit 1
    fi
else
    echo "Current linux branch is not ${TCDIST_LINUX_BRANCH}" >&2
    exit 1
fi
