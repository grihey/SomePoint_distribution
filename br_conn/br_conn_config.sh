#!/bin/bash
# shellcheck disable=SC2034 # disable unused variable warnings

TCDIST_VM_NAME="br_conn"

function Arfs_interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "auto eth1"
    echo "iface eth1 inet static"
    echo "    address ${TCDIST_INTERNAL_NET}.1"
    echo "    netmask 255.255.255.0"
    echo ""
    echo "iface default inet dhcp"
}

function Arfs_net_rc_add {
    echo "#!/bin/bash"
    echo ""
    echo "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
    echo "iptables -t nat -A PREROUTING -p tcp --dport 222 -j DNAT --to-destination ${TCDIST_INTERNAL_NET}.2:22"
    echo "echo \"1\" > /proc/sys/net/ipv4/ip_forward"
    echo ""
    echo "echo \"nameserver ${TCDIST_DEVICEDNS}\" > /etc/resolv.conf"
}

TCDIST_VM_INPUTS="vm_1.sh"
TCDIST_VM_OUTPUTS="${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.ext2 ${TCDIST_VM_NAME}_${TCDIST_ARCH}_${TCDIST_PLATFORM}.${TCDIST_KERNEL_IMAGE_FILE}"

ARFS_OPTIONS="-hostname -interfaces -ssh -inittab s -netrcadd"
