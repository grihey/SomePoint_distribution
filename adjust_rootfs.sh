#!/bin/bash
# Generic base for rootfs adjust script
# It is assumed that this is sourced from vm-specific rootfs adjust script

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
        echo "tty2::respawn:/sbin/getty -L tty2 0 vt100 # VGA console"
        echo "tty3::respawn:/sbin/getty -L tty3 0 vt100 # VGA console"
        echo "tty4::respawn:/sbin/getty -L tty4 0 vt100 # VGA console"
    fi

    cat "${TCDIST_DIR}/configs/inittab.post"
}

function Arfs_net_rc_add {
    echo "#!/bin/bash"
    echo ""
    echo "echo \"nameserver ${TCDIST_DEVICEDNS}\" > /etc/resolv.conf"
}

function Arfs_load_config {
    local sdir

    # Get actual directory of this bash script
    sdir="$(dirname "${BASH_SOURCE[0]}")"
    sdir="$(realpath "$sdir")"

    set -e

    # Shellcheck doesn't know what is included here, disable complaint.
    # shellcheck disable=SC1090
    . "${sdir}/helpers.sh"

    Load_config

    if [ -n "${TCDIST_VM_NAME}" ]; then
        # Load vm specific config
        # Shellcheck doesn't know what is included here, disable complaint.
        # shellcheck disable=SC1090
        . "${TCDIST_DIR}/${TCDIST_VM_NAME}/${TCDIST_VM_NAME}_config.sh"
    fi
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
        Arfs_hostname > "${TCDIST_TMPDIR}"/hostname.tmp
        e2cp -P 644 -O 0 -G 0 "${TCDIST_TMPDIR}"/hostname.tmp "${2}:/etc/hostname"
        rm -f "${TCDIST_TMPDIR}"/hostname.tmp
        set +x
    fi

    # Set network interfaces if requested
    if [ -n "$interfaces" ]; then
        set -x
        Arfs_interfaces > "${TCDIST_TMPDIR}"/interfaces.tmp
        e2cp -P 644 -O 0 -G 0 "${TCDIST_TMPDIR}"/interfaces.tmp "${2}:/etc/network/interfaces"
        rm -f "${TCDIST_TMPDIR}"/interfaces.tmp
        set +x
    fi

    # Set inittab if requested
    if [ -n "$inittab" ]; then
        set -x
        Arfs_inittab "$inittab_opt" > "${TCDIST_TMPDIR}"/inittab.tmp
        e2cp -P 644 -O 0 -G 0 "${TCDIST_TMPDIR}"/inittab.tmp "${2}:/etc/inittab"
        rm -f "${TCDIST_TMPDIR}"/inittab.tmp
        set +x
    fi

    # Set net additions if requested
    if [ -n "$netrcadd" ]; then
        set -x
        Arfs_net_rc_add > "${TCDIST_TMPDIR}"/net_rc_add.tmp
        e2cp -P 744 -O 0 -G 0 "${TCDIST_TMPDIR}"/net_rc_add.tmp "${2}:/etc/init.d/S41netadditions"
        rm -f "${TCDIST_TMPDIR}"/net_rc_add.tmp
        set +x
    fi
}

function Check_script {
    local scriptlist

    Arfs_load_config

    scriptlist="./adjust_rootfs.sh"
    scriptlist+=" ${TCDIST_DIR}/adjust_rootfs.sh"
    scriptlist+=" ${TCDIST_DIR}/helpers.sh"
    scriptlist+=" ${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT}"

    if [ -n "${TCDIST_VM_NAME}" ]; then
        scriptlist+=" ${TCDIST_DIR}/${TCDIST_VM_NAME}/${TCDIST_VM_NAME}_config.sh"
    fi

    # scriptlist is space separated list of files, purposefully unquoted
    # shellcheck disable=SC2086
    Shellcheck_bashate $scriptlist
    exit
}

if [ "$1" == "check_script" ]; then
    Check_script
fi
