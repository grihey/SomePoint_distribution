#!/bin/bash

function On_exit_cleanup {
    set +e
    if [ -n "$TCDIST_TMPDIR" ]; then
        rm -rf "$TCDIST_TMPDIR"
    fi
    popd > /dev/null
}

# Stop script on error
set -e

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

# Save original working dir
OPWD=$PWD

# Change to the script directory and set cleanup on exit
pushd "$SDIR" > /dev/null
trap On_exit_cleanup EXIT

. helpers.sh

function Clone {
    git submodule init
    git submodule update -f
    if [ -f ~/.gitconfig ]; then
        cp ~/.gitconfig docker/gitconfig
    else
        echo "~/.gitconfig not found. Please copy your .gitconfig to ./docker/gitconfig manually." >&2
    fi

    # Make sure all branches are available in linux repo
    Fetch_all linux

    # Checkout the default branch
    (
        cd linux
        git checkout "${TCDIST_LINUX_BRANCH}"
    )
}

function Ssh_config_item {
    local vm_name
    local identity_file
    local port
    local username
    local host

    vm_name=$1
    identity_file=$2
    port=$3
    username=$4
    host=$5

    echo ""
    echo "Host ${vm_name}"
    echo "    HostName               ${host}"
    echo "    User                   ${username}"
    echo "    IdentityFile           ${identity_file}"
    echo "    Port                   ${port}"
    echo "    UserKnownHostsFile     /dev/null"
    echo "    StrictHostKeyChecking  no"
    echo "    PasswordAuthentication no"
    if [[ "${vm_name}" == "br_conn" || "${vm_name}" == "br_secure" ]]
    then
        echo "    ProxyJump              br_admin"
    fi
}

function Ssh_config {
    local vm
    local ssh_port
    local target_file

    target_file="${TCDIST_OUTPUT}/ssh_config"

    {
    echo "# Generated configuration to connect SecureOS machines"
    echo "# To use, add the following to your ~/.ssh/config:"
    echo "#    Include ${target_file}"
    echo "# or ssh -F ${TCDIST_OUTPUT}/ssh_config br_admin"
    } > "${target_file}"

    for vm in $TCDIST_VMLIST; do
        case "$vm" in
        br_conn)
            ssh_port=2301
        ;;
        br_secure)
            ssh_port=2302
        ;;
        *)
            ssh_port=2222
        esac

        Ssh_config_item "${vm}" "${TCDIST_OUTPUT}/${vm}/device_id_rsa" \
            "${ssh_port}" root localhost \
            >> "$target_file"
    done

    echo "SSH config created to ${target_file}"

    # Just check if ssh config has mention of the filename
    # -- don't mind if it's commented out or so
    if ! grep -Fq "${target_file}" ~/.ssh/config
    then
        echo "Config NOT IN USE"
        echo "Please add following to your ~/.ssh/config:"
        echo ""
        echo "Include ${target_file}"
        echo ""
        echo "(or run)"
        echo "echo \"Include ${target_file}\" >> ~/.ssh/config"
    fi
}

function Ssh_dut {
    local dut_ip
    local subnet
    local st
    local ip
    local ips
    local vm_id
    local ssh_port

    case "$1" in
    domu)
        case "$TCDIST_ARCH" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@$TCDIST_DEVICEIP"
        ;;
        esac
    ;;
    vm_*)
        # SSH to target VM, e.g. vm_admin. The code below checks if the IP
        # address for the VM is known already (.br_admin.ip.tmp file exists),
        # and we check with ping to see if the IP address is still valid or
        # whether it has gone stale. In case we don't know the current IP
        # address for the VM, we attempt to discover it with use of NMAP
        # over the network bridge that is used for the VM network
        vm_id=$1
        case "$TCDIST_ARCH" in
        x86)
            vm_id=${vm_id/#vm_/br_}

            case "$vm_id" in
            br_secure)
                ssh_port=222
            ;;
            *)
                ssh_port=2222
            ;;
            esac

            # Check if we know VM IP address already
            if [ -f "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp" ] ; then
                dut_ip=$(cat "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp")
                set +e

                # Check if the VM responds to ping (i.e., our IP address is still valid)
                st=$(ping -c 1 -W 1 "$dut_ip" | grep "from $dut_ip")
                set -e
                if [ -z "${st}" ] ; then
                    # No response, mark our address as invalid
                    dut_ip=""
                fi
            fi
            if [ -z ${dut_ip} ] ; then
                echo "No DUT IP known, exploring..."
                rm -f "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp"

                # Generate subnet mask for our bridge, get current IP address
                # for it and grab first three values.
                subnet=$(ifconfig | grep -A 1 "$TCDIST_ADMIN_BRIDGE" | grep -o "inet [0-9\.]*" | cut -d " " -f 2 | cut -d "." -f 1-3)
                echo "Our subnet is ${subnet}.0/24"

                # Scan the generated subnet for anybody home, cut first address
                # away as that is our own address
                ips=$(nmap -sP "${subnet}.0/24" | grep "${subnet}" | tail -n +2 | grep -o "[0-9\.]*")
                set +e

                # We have a list of everybody in the subnet, now try our
                # VM SSH key against each to see which of them accepts it,
                # and run "uname -a" on them to match our target VM name.
                for ip in ${ips} ; do
                    echo "Trying IP: $ip"
                    st=$(ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p "$ssh_port" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no "root@${ip}" uname -a | grep "${vm_id}")
                    if [ -n "$st" ] ; then
                        echo "IP $ip mapped to dut"
                        dut_ip=$ip
                    fi
                done

                # Attempt localhost in case qemu is using slirp network
                st=$(ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no "root@localhost" uname -a | grep "${vm_id}")
                if [ -n "$st" ] ; then
                    echo "IP localhost mapped to dut"
                    dut_ip="localhost"
                fi
                set -e

                # Found our target IP address, save it for later use as the
                # VMs in most cases retain their IP address.
                echo "$dut_ip" > "${TCDIST_OUTPUT}/${vm_id}/.ip.tmp"
            fi

            ssh -i "${TCDIST_OUTPUT}/${vm_id}/device_id_rsa" -p "$ssh_port" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@${dut_ip}"
        ;;
        esac
    ;;
    *)
        case "$TCDIST_ARCH" in
        x86)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 222 "root@127.0.0.1"
        ;;
        *)
            ssh -i images/device_id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "root@$TCDIST_DEVICEIP"
        ;;
        esac
    esac
}

function Clean {
    Make clean
}

function Distclean {
    Make distclean
}

function Shell {
    if [ ! -f docker/gitconfig ]; then
        make -C docker build_env
    fi
    make -C docker shell
}

function Check_script {
    Shellcheck_bashate setup.sh helpers.sh ${TCDIST_OUTPUT}/.setup_sh_config_${TCDIST_PRODUCT}
}

function Show_help {
    echo "Usage $0 <command> [parameters]"
    echo ""
    echo "Commands:"
    echo "    defconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} from defaults"
    echo "    xenconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} for xen"
    echo "    kvmconfig                         Create new ${TCDIST_SETUP_SH_CONFIG} for kvm"
    echo "    x86config                         Create new ${TCDIST_SETUP_SH_CONFIG} for x86"
    echo "    x86config_upxtreme                Create new ${TCDIST_SETUP_SH_CONFIG} for x86 upXtreme"
    echo "    arm64config                       Create new ${TCDIST_SETUP_SH_CONFIG} for raspi4"
    echo "    arm64config_ls1012a               Create new ${TCDIST_SETUP_SH_CONFIG} for nxp ls1012a-frwy"
    echo "    arm64config_cm4io                 Create new ${TCDIST_SETUP_SH_CONFIG} for cm4io"
    echo "    clone                             Clone the required subrepositories"
    echo "    ssh_dut [domu]                    Open ssh session with target device"
    echo "    shell                             Open docker shell"
    echo "    distclean                         removes almost everything except main repo local changes"
    echo "    clean                             Clean up built files"
    echo "    check_script                      Check setup.sh script (and sourced scripts) with"
    echo "                                      shellcheck and bashate"
    echo "    install_completion                Install bash completion for setup.sh commands"
    echo "    ssh_config                        Create ssh configuration"
    echo "    make [parameters]                 Run make with current config. (All parameters are passed to make)"
    echo ""
    exit 0
}

function Install_completion {
    echo 'complete -W "defconfig xenconfig kvmconfig x86config clone ssh_dut shell distclean clean check_script make" setup.sh' | sudo tee /etc/bash_completion.d/setup.sh_completion > /dev/null
    echo "Bash auto completion installed (you need to reopen bash shell for changes to be in effect)"
}

# Convert command to all lower case and then convert first letter to upper case
CMD="${1,,}"
CMD="${CMD^}"

# Some aliases for legacy and clearer function names
case "$CMD" in
    ""|Help|-h|--help)
        Load_config
        Show_help >&2
    ;;
    Defconfig)
        CMD="Xenconfig"
    ;;
    *)
        # Default, no conversion
    ;;
esac

shift

case "$CMD" in
    Xenconfig|Kvmconfig|X86config|Arm64config|Arm64config_ls1012a|Arm64config_cm4io)
        set -a
        TCDIST_SETUP_SH_CONFIG=".setup_sh_config${TCDIST_PRODUCT}"
        set +a
        Min_config
    ;;
    Clean|Distclean)
        # Do not check config if cleaning
        Load_config nocheck
    ;;
    *)
        Load_config
    ;;
esac

# Check if function exists and run it if it does
Fn_exists "$CMD"
"$CMD" "$@"
