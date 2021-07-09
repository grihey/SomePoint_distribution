#!/bin/bash
# Generic base for rootfs adjust script
# It is assumed that this is sourced from vm-specific rootfs adjust script

ARFS_CURVM="$(pwd)"
ARFS_CURVM="${ARFS_CURVM##*/}"

# Defaults, these can be overridden in vm-specific config script

function Arfs_hostname {
    echo "${TCDIST_VM_NAME}"
}

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "iface eth0 inet manual"
    echo ""
    echo "iface default inet dhcp"
}

function Arfs_inittab {
    cat "${TCDIST_DIR}/configs/inittab.pre"

    if [[ "$1" =~ s ]]; then
        echo "cons::respawn:/sbin/getty -L console 0 vt100 # Generic Serial"
    fi
    if [[ "$1" =~ v ]]; then
        echo "tty1::respawn:/sbin/getty -L tty1 0 vt100 # VGA console"
    fi

    cat "${TCDIST_DIR}/configs/inittab.post"
}

function Arfs_net_rc_add {
    echo "#!/bin/bash"
    echo ""
    echo "echo \"nameserver ${TCDIST_DEVICEDNS}\" > /etc/resolv.conf"
}

function Arfs_load_config {
    set -e

    . ../helpers.sh
    . ../text_generators.sh

    Load_config

    # Load vm specific config
    # Shellcheck doesn't know what is included here, disable complaint.
    # shellcheck disable=SC1090
    . "./${ARFS_CURVM}_config.sh"
}

function Arfs_apply {
    local hostname
    local inittab
    local inittab_opt
    local interfaces
    local netrcadd
    local ssh

    while [ "${1:0:1}" == "-" ]; do
        case "$1" in
            -hostname)
                hostname=1
            ;;
            -interfaces)
                interfaces=1
            ;;
            -ssh)
                ssh=1
            ;;
            -inittab)
                inittab=1
                inittab_opt="$2"
                shift
            ;;
            -netrcadd)
                netrcadd=1
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

    # Check that we have two image names
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: Arfs_apply [options] <input image> <output image>"
        echo ""
        exit 1
    fi

    # Just copy the source ext2 file to output file
    set -x
    cp -f "$1" "$2"
    set +x

    if [ -n "$ssh" ] ; then
        set -x
        # Generate ssh key
        if ! [ -a "${TCDIST_OUTPUT}/${TCDIST_VM_NAME}/device_id_rsa" ] ; then
            ssh-keygen -t rsa -q -f "${TCDIST_OUTPUT}/${TCDIST_VM_NAME}/device_id_rsa" -N ""
        fi

        e2mkdir "${2}:/root/.ssh" -P 700 -G 0 -O 0
        e2cp "${TCDIST_OUTPUT}/${TCDIST_VM_NAME}/device_id_rsa.pub" "${2}:/root/.ssh/authorized_keys" -P 700 -G 0 -O 0
        set +x
    fi

    # Set hostname if requested
    if [ -n "$hostname" ]; then
        set -x
        Arfs_hostname > hostname.tmp
        e2cp -P 644 -O 0 -G 0 hostname.tmp "${2}:/etc/hostname"
        rm -f hostname.tmp
        set +x
    fi

    # Set network interfaces if requested
    if [ -n "$interfaces" ]; then
        set -x
        Arfs_interfaces > interfaces.tmp
        e2cp -P 644 -O 0 -G 0 interfaces.tmp "${2}:/etc/network/interfaces"
        rm -f interfaces.tmp
        set +x
    fi

    # Set inittab if requested
    if [ -n "$inittab" ]; then
        set -x
        Arfs_inittab "$inittab_opt" > inittab.tmp
        e2cp -P 644 -O 0 -G 0 inittab.tmp "${2}:/etc/inittab"
        rm -f inittab.tmp
        set +x
    fi

    # Set net additions if requested
    if [ -n "$netrcadd" ]; then
        set -x
        Arfs_net_rc_add > net_rc_add.tmp
        e2cp -P 744 -O 0 -G 0 net_rc_add.tmp "${2}:/etc/init.d/S41netadditions"
        rm -f net_rc_add.tmp
        set +x
    fi
}

if [ "$1" == "check_script" ]; then
    Arfs_load_config
    Shellcheck_bashate ./adjust_rootfs.sh ../adjust_rootfs.sh ../helpers.sh ../text_generators.sh ../default_setup_sh_config "./${ARFS_CURVM}_config.sh"
    exit
fi
