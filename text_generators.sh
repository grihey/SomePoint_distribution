#!/bin/bash

# Configuration file text generators
# Included into setup.sh

function Domu_config {
    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        echo "kernel = \"/root/Image\""
        echo "cmdline = \"console=hvc0 earlyprintk=xen sync_console root=/dev/nfs rootfstype=nfs nfsroot=${TCDIST_NFSSERVER}:${TCDIST_NFSDOMU},tcp,rw,vers=3 ip=10.123.123.2::10.123.123.1:255.255.255.0:${TCDIST_DEVICEHN}-domu:eth0:off:${TCDIST_DEVICEDNS}\""
        echo "memory = \"1024\""
        echo "name = \"rpi4-xen-guest\""
        echo "vcpus = 2"
        echo "cpus = \"3-4\""
        echo "serial=\"pty\""
        echo "disk = [  ]"
        echo "vif=[ 'mac=FA:CE:C0:FF:EE:00,ip=10.123.123.2' ]"
        echo "vfb = [ 'type=vnc,vncdisplay=10,vncpasswd=raspberry' ]"
        echo "type = \"pvh\""
        echo ""
        echo "# Guest VGA console configuration, either SDL or VNC"
        echo "#sdl = 1"
        echo "vnc = 1"
    ;;
    *)
        cat "configs/domu.cfg.${TCDIST_BUILDOPT}"
    ;;
    esac
}

function Dom0_interfaces {
    case "$TCDIST_HYPERVISOR" in
    kvm)
        case "$TCDIST_BUILDOPT" in
        dhcp)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet dhcp"
            echo ""
            echo "iface default inet dhcp"
        ;;
        static)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet static"
            echo "    address ${TCDIST_DEVICEIP}"
            echo "    netmask ${TCDIST_DEVICENM}"
            echo "    gateway ${TCDIST_DEVICEGW}"
            echo ""
            echo "iface default inet dhcp"
        ;;
        *)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "auto eth0"
            echo "iface eth0 inet dhcp"
            echo ""
            echo "iface default inet dhcp"
        ;;
        esac
    ;;
    *)
        case "$TCDIST_BUILDOPT" in
        dhcp)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet dhcp"
            echo ""
            echo "iface default inet dhcp"
        ;;
        static)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet static"
            echo "    address ${TCDIST_DEVICEIP}"
            echo "    netmask ${TCDIST_DEVICENM}"
            echo "    gateway ${TCDIST_DEVICEGW}"
            echo ""
            echo "iface default inet dhcp"
        ;;
        *)
            cat configs/interfaces
        ;;
        esac
    ;;
    esac
}

function Domu_interfaces {
    case "$TCDIST_HYPERVISOR" in
    kvm)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        case "$TCDIST_BUILDOPT" in
        dhcp)
            echo "iface eth0 inet dhcp"
        ;;
        static)
            echo "iface eth0 inet static"
            echo "    address 10.0.2.15"
            echo "    netmask 255.255.255.0"
            echo "    gateway 10.0.2.2"
        ;;
        *)
            echo "auto eth0"
            echo "iface eth0 inet dhcp"
        ;;
        esac
        echo ""
        echo "iface default inet dhcp"
    ;;
    *)
        case "$TCDIST_BUILDOPT" in
        static)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet static"
            echo "    address 10.123.123.2"
            echo "    netmask 255.255.255.0"
            echo "    gateway 10.123.123.1"
            echo ""
            echo "iface default inet dhcp"
        ;;
        dhcp)
            echo "auto lo"
            echo "iface lo inet loopback"
            echo ""
            echo "iface eth0 inet dhcp"
            echo ""
            echo "iface default inet dhcp"
        ;;
        *)
            cat configs/interfaces
        ;;
        esac
    ;;
    esac
}

function Uboot_stub {
    case "$TCDIST_BUILDOPT" in
    mmc)
        echo "fatload mmc 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    dhcp)
        echo "dhcp 0x100000 ${TCDIST_TFTPSERVER}:boot2.scr"
        echo "setenv serverip ${TCDIST_TFTPSERVER}"
        echo "source 0x100000"
    ;;
    static)
        echo "setenv ipaddr ${TCDIST_DEVICEIP}"
        echo "setenv netmask ${TCDIST_DEVICENM}"
        echo "setenv serverip ${TCDIST_TFTPSERVER}"
        echo "tftp 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    *)
        echo "fatload usb 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    esac
}

function Fdt_addr {
    case "$TCDIST_FWFDT" in
    1)
        # No address set in this case
    ;;
    *)
        echo "setenv fdt_addr ${1}"
    ;;
    esac
}

function Fdt_load {
    case "$TCDIST_FWFDT" in
    1)
        # No load in this case
    ;;
    *)
        echo "${1} 0x\${fdt_addr} ${TCDIST_DEVTREE}"
    ;;
    esac
}

function Uboot_source {
    local BOOTARGS="dwc_otg.lpm_enable=0"

    case "$TCDIST_HYPERVISOR" in
    kvm)
        local CONSOLE=" console=tty1 console=ttyS0,115200"
        local ADDITIONAL=""
    ;;
    *)
        local CONSOLE=" console=hvc0 earlycon=xen earlyprintk=xen"
        local ADDITIONAL=" elevator=deadline"
    ;;
    esac

    case "$TCDIST_BUILDOPT" in
    mmc)
        local LOAD="fatload mmc 0:1"
        local ROOTPARM=" root=/dev/mmcblk0p2 rootfstype=ext4"
    ;;
    dhcp|static)
        local LOAD="tftp"
        local ROOTPARM=" root=/dev/nfs rootfstype=nfs nfsroot=${TCDIST_NFSSERVER}:${TCDIST_NFSDOM0},tcp,rw,vers=3 ip=${TCDIST_DEVICEIPCONF}"
    ;;
    *)
        local LOAD="fatload usb 0:1"
        local ROOTPARM=" root=/dev/sda2 rootfstype=ext4"
    ;;
    esac

    BOOTARGS+="$CONSOLE"
    BOOTARGS+="$ROOTPARM"
    BOOTARGS+="$ADDITIONAL"
    BOOTARGS+=" rootwait fixrtc splash"

    echo "setenv uenv_addr ff0000"
    echo "if $LOAD 0x\${uenv_addr} uEnv.txt; then"
    echo "	echo 'Loaded env from uEnv.txt';"
    echo "	echo 'Importing environment from uEnv.txt';"
    echo "	env import -t \${uenv_addr} \${filesize};"
    echo "fi"
    echo "if test -n \${uenvcmd}; then"
    echo "	echo 'Running uenvcmd ...';"
    echo "	run uenvcmd;"
    echo "fi"
    echo

    Fdt_addr 2600000
    Fdt_load "$LOAD"
    echo "fdt addr \${fdt_addr}"
    echo "setenv lin_addr 1000000"
    echo "${LOAD} 0x\${lin_addr} vmlinuz"

    case "$TCDIST_HYPERVISOR" in
    kvm)
        echo "setenv bootargs \"${BOOTARGS}\""
        echo "setenv fdt_high 0xffffffffffffffff"
        echo "booti 0x\${lin_addr} - 0x\${fdt_addr}"
    ;;
    *)
        echo "setenv lin_size \$filesize"
        echo "setenv xen_addr E00000"
        echo "${LOAD} 0x\${xen_addr} xen"
        echo "fdt resize 1024"
        echo "fdt set /chosen \\#address-cells <1>"
        echo "fdt set /chosen \\#size-cells <1>"
        echo "fdt set /chosen xen,xen-bootargs \"console=dtuart dtuart=serial0 sync_console dom0_mem=${TCDIST_XEN_DOM0_MEMORY:?} dom0_max_vcpus=${TCDIST_XEN_DOM0_CPUCOUNT:?} bootscrub=0 vwfi=native sched=credit2\""
        echo "fdt mknod /chosen dom0"
        echo "fdt set /chosen/dom0 compatible \"xen,linux-zimage\" \"xen,multiboot-module\""
        echo "fdt set /chosen/dom0 reg <0x\${lin_addr} 0x\${lin_size}>"
        echo "fdt set /chosen xen,dom0-bootargs \"${BOOTARGS}\""
        echo "setenv fdt_high 0xffffffffffffffff"
        echo "booti 0x\${xen_addr} - 0x\${fdt_addr}"
    ;;
    esac
}

function Net_rc_add {
    echo "#!/bin/bash"
    echo ""

    if [ "$1" == "dom0" ] && [ "$TCDIST_HYPERVISOR" == "kvm" ] ; then
        # Allow ping from guest VMs under kvm
        echo "sysctl -w net.ipv4.ping_group_range='0 2147483647'"
    fi

    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        if [ "$1" == "dom0" ] && [ "$TCDIST_HYPERVISOR" == "xen" ] ; then
            echo "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
            echo "iptables -t nat -A PREROUTING -p tcp --dport 222 -j DNAT --to-destination 10.123.123.2:22"
            echo "echo \"1\" > /proc/sys/net/ipv4/ip_forward"
            echo ""
        fi

        echo "DNSS=\$(dmesg | grep nameserver0)"
        echo "if [ \"\$?\" -eq 0 ]; then"
        echo "    read -r _ _ DNS0 <<< \"\$DNSS\""
        echo "    DNS0=\${DNS0##*nameserver0=}"
        echo "    DNS0=\${DNS0%%,*}"
        echo "else"
        echo "    DNS0=${TCDIST_DEVICEDNS}"
        echo "fi"
        echo ""
        echo "echo \"nameserver \$DNS0\" > /etc/resolv.conf"
    ;;
    *)
    ;;
    esac
}

function Inittab {
    case "$1" in
    dom0)
        cat configs/inittab.pre

        case "$TCDIST_HYPERVISOR" in
        kvm)
            echo "#AMA0::respawn:/sbin/getty -L ttyAMA0 0 vt100 # Raspi serial"
            echo "tty1::respawn:/sbin/getty -L tty1 0 vt100 # HDMI console"
            echo "S0::respawn:/sbin/getty -L ttyS0 0 vt100 # Serial console"
            #if [ "$TCDIST_ARCH" = "x86" ] ; then
            #    echo "cons::respawn:/sbin/getty -L console 0 vt100 # Generic Serial"
            #fi
        ;;
        *)
            echo "X0::respawn:/sbin/getty 115200 /dev/hvc0 # Xen virtual serial"
            echo "tty1::respawn:/sbin/getty -L tty1 0 vt100 # HDMI console"
        ;;
        esac
        cat configs/inittab.post
    ;;
    domu)
        cat configs/inittab.pre
        case "$TCDIST_HYPERVISOR" in
        kvm)
            if [ "$TCDIST_ARCH" = "x86" ] ; then
                echo "cons::respawn:/sbin/getty -L console 0 vt100 # Generic serial"
            else
                echo "AMA0::respawn:/sbin/getty -L ttyAMA0 0 vt100 # kvm virtual serial"
            fi
        ;;
        *)
            echo "X0::respawn:/sbin/getty 115200 /dev/hvc0 # Xen virtual serial"
        ;;
        esac
        cat configs/inittab.post
    ;;
    *)
        echo "Invalid Inittab option" >&2
        exit 2
    ;;
    esac
}

function Config_txt {
    case "$TCDIST_HYPERVISOR" in
    kvm)
        cat configs/config_kvm.txt
    ;;
    *)
        cat configs/config_xen.txt
    ;;
    esac
}

function Rq_sh {
    echo "#!/bin/bash"
    case "$TCDIST_PLATFORM" in
    x86)
        echo "./run-x86-qemu.sh \"\$@\""
    ;;
    *)
        case "$TCDIST_BUILDOPT" in
        mmc)
            echo "./run-qemu.sh /dev/mmcblk0p3 \"\$@\""
        ;;
        dhcp|static)
            echo "./run-qemu.sh /dev/nfs ${TCDIST_NFSSERVER}:${TCDIST_NFSDOMU} \"\$@\""
        ;;
        *)
            echo "./run-qemu.sh /dev/sda3 \"\$@\""
        ;;
        esac
    ;;
    esac
}

function Run_x86_qemu_sh {
    echo "#!/bin/bash"
    case "$TCDIST_BUILDOPT" in
    dhcp|static)
        if [ "$TCDIST_SECUREOS" = "1" ] ; then
            echo "ROOTFS_FILE=\"-drive file=docker.ext2,if=virtio,format=raw\""
        else
            echo "ROOTFS_FILE=\"\""
        fi

        echo "ROOTFS_CMD=\"root=/dev/nfs nfsroot=${TCDIST_NFSSERVER}:${TCDIST_NFSDOMU},tcp,vers=3,nolock ip=::::${TCDIST_DEVICEHN}-domu:eth0:dhcp\""
    ;;
    *)
        echo "ROOTFS_FILE=\"-drive file=rootfs.ext2,if=virtio,format=raw\""
        echo "ROOTFS_CMD=\"root=/dev/vda\""
    ;;
    esac
    echo "qemu-system-x86_64 -m 256 -M pc -device vhost-vsock-pci,id=vhost-vsock-pci0,guest-cid=3,disable-legacy=on -enable-kvm \\"
    echo "    -kernel Image \${ROOTFS_FILE} -append \"rootwait \${ROOTFS_CMD} console=tty1 console=ttyS0\" \\"
    echo "    -net nic,model=virtio -net user,hostfwd=tcp::222-:22 -nographic \"\$@\""
}

function Virt_socat_sh {
    echo "#!/bin/bash"
    echo "set -x"
    echo "socat - SOCKET-LISTEN:40:0:x00x00x00x04x00x00x03x00x00x00x00x00x00x00"
}

function Host_socat_sh {
    echo "#!/bin/bash"
    echo "set -x"
    echo "socat - SOCKET-CONNECT:40:0:x00x00x00x04x00x00x03x00x00x00x00x00x00x00"
}

# Azure wg server settings.
function Wg_client_config {
    echo "[Interface]"
    echo "Address = 10.10.10.2/24"
    echo "DNS = 10.10.10.1"
    echo "PrivateKey = +Lr/45I4KF+EeE3kZ0p/0GKxKp4Cjj+bGMtGFYw97U0="
    echo ""
    echo "[Peer]"
    echo "PublicKey = 8Rvz/ER24u/w2y4tiqpsEthEJJNAO3OGmdNpArimBjA="
    echo "AllowedIPs = 0.0.0.0/0"
    echo "Endpoint = 52.169.138.111:51820"
    echo "PersistentKeepalive = 25"
}

function Mount_debug_fs {
    echo "debugfs    /sys/kernel/debug      debugfs  defaults  0 0"
}
