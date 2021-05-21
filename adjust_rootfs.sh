#!/bin/bash
# Generic base for rootfs adjust script
# It is assumed that this is run from vm-specific rootfs adjust script

# Defaults, these can be overridden in vm-specific config script

function Hostname {
    echo "${CURVM}"
}

function Interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "iface eth0 inet manual"
    echo ""
    echo "iface default inet dhcp"
}

set -e

# It is assumed here that this script is sourced from the specific vm directory
# And so we get the name of the vm in question
CURVM="$(pwd)"
CURVM="${CURVM##*/}"

. ../helpers.sh
Load_config

if [ "$1" == "check_script" ]; then
    Shellcheck_bashate ./adjust_rootfs.sh ../adjust_rootfs.sh ../helpers.sh ../default_setup_sh_config "./${CURVM}_config.sh"
    exit $?
fi

while [ "${1:0:1}" == "-" ]; do
    case "$1" in
        -hostname|-hn)
            ARFS_HOSTNAME=1
        ;;
        -interfaces|if)
            ARFS_INTERFACES=1
        ;;
        --)
            # explicit end of options
            shift
            break
        ;;
        -*)
            echo Unknown option: "$1" >&2
            exit 1
        ;;
        *)
            # Assume image names encountered
            break
        ;;
    esac
    shift
done

# Load vm specific config
# Shellcheck doesn't know what is included here, disable complaint.
# shellcheck disable=SC1090
. "./${CURVM}_config.sh"

# Check that we have two image names
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./adjust_rootfs.sh [options] <input image> <output image>"
    echo ""
    exit 1
fi

# Just copy the source ext2 file to output file
set -x
cp -f "$1" "$2"
set +x

# Set hostname if requested
if [ -n "$ARFS_HOSTNAME" ]; then
    set -x
    Hostname > hostname.tmp
    e2cp -P 644 -O 0 -G 0 hostname.tmp "${2}:/etc/hostname"
    rm -f hostname.tmp
    set +x
fi

# Set network interfaces if requested
if [ -n "$ARFS_INTERFACES" ]; then
    set -x
    Interfaces > interfaces.tmp
    e2cp -P 644 -O 0 -G 0 interfaces.tmp "${2}:/etc/network/interfaces"
    rm -f interfaces.tmp
    set +x
fi

