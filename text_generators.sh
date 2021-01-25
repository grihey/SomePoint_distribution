# Configuration file text generators
# Included into setup.sh

function domu_config {
    case "$BUILDOPT" in
    0)
        cat configs/domu.cfg.sd
    ;;
    1)
        cat configs/domu.cfg.usb
    ;;
    2|3)
        echo "kernel = \"/root/Image\""
        echo "cmdline = \"console=hvc0 earlyprintk=xen sync_console root=/dev/nfs rootfstype=nfs nfsroot=${NFSSERVER}:${NFSDOMU},tcp,rw,vers=3 ip=10.123.123.2::10.123.123.1:255.255.255.0:${RASPHN}-domu:eth0:off:${RASPDNS}\""
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
    esac
}

function dom0_interfaces {
    case "$BUILDOPT" in
    2)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        echo "iface eth0 inet dhcp"
        echo ""
        echo "iface default inet dhcp"
    ;;
    3)
        echo "auto lo"
        echo "iface lo inet loopback"
        echo ""
        echo "iface eth0 inet static"
        echo "    address ${RASPIP}"
        echo "    netmask ${RASPNM}"
        echo "    gateway ${RASPGW}"
        echo ""
        echo "iface default inet dhcp"
    ;;
    *)
        cat configs/interfaces
    ;;
    esac
}

function domu_interfaces {
    case "$BUILDOPT" in
    2|3)
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
    *)
        cat configs/interfaces
    ;;
    esac
}

function ubootstub {
    case "$BUILDOPT" in
    0)
        echo "fatload mmc 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    1)
        echo "fatload usb 0:1 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    2)
        echo "dhcp 0x100000 ${TFTPSERVER}:boot2.scr"
        echo "setenv serverip ${TFTPSERVER}"
        echo "source 0x100000"
    ;;
    3)
        echo "setenv ipaddr ${RASPIP}"
        echo "setenv netmask ${RASPNM}"
        echo "setenv serverip ${TFTPSERVER}"
        echo "tftp 0x100000 boot2.scr"
        echo "source 0x100000"
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac
}

function fdt_addr {
    case "$FWFDT" in
    1)
        # No address set in this case
    ;;
    *)
        echo "setenv fdt_addr ${1}"
    ;;
    esac
}

function fdt_load {
    case "$FWFDT" in
    1)
        # No load in this case
    ;;
    *)
        echo "${1} 0x\${fdt_addr} ${DEVTREE}"
    ;;
    esac
}

function ubootsource {
    local BOOTARGS="dwc_otg.lpm_enable=0"

    case "$HYPERVISOR" in
    KVM)
        local CONSOLE=" console=tty1"
        local ADDITIONAL=""
    ;;
    *)
        local CONSOLE=" console=hvc0 earlycon=xen earlyprintk=xen"
        local ADDITIONAL=" elevator=deadline"
    ;;
    esac

    case "$BUILDOPT" in
    0)
        local LOAD="fatload mmc 0:1"
        local ROOTPARM=" root=/dev/mmcblk0p2 rootfstype=ext4"
    ;;
    1)
        local LOAD="fatload usb 0:1"
        local ROOTPARM=" root=/dev/sda2 rootfstype=ext4"
    ;;
    2|3)
        local LOAD="tftp"
        local ROOTPARM=" root=/dev/nfs rootfstype=nfs nfsroot=${NFSSERVER}:${NFSDOM0},tcp,rw,vers=3 ip=${IPCONFRASPI}"
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac

    BOOTARGS+="$CONSOLE"
    BOOTARGS+="$ROOTPARM"
    BOOTARGS+="$ADDITIONAL"
    BOOTARGS+=" rootwait fixrtc splash"

    fdt_addr 2600000
    fdt_load "$LOAD"
    echo "fdt addr \${fdt_addr}"
    echo "setenv lin_addr 1000000"
    echo "${LOAD} 0x\${lin_addr} vmlinuz"

    case "$HYPERVISOR" in
    KVM)
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
        echo "fdt set /chosen xen,xen-bootargs \"console=dtuart dtuart=serial0 sync_console dom0_mem=4G dom0_max_vcpus=2 bootscrub=0 vwfi=native sched=null\""
        echo "fdt mknod /chosen dom0"
        echo "fdt set /chosen/dom0 compatible \"xen,linux-zimage\" \"xen,multiboot-module\""
        echo "fdt set /chosen/dom0 reg <0x\${lin_addr} 0x\${lin_size}>"
        echo "fdt set /chosen xen,dom0-bootargs \"${BOOTARGS}\""
        echo "setenv fdt_high 0xffffffffffffffff"
        echo "booti 0x\${xen_addr} - 0x\${fdt_addr}"
    ;;
    esac
}

function net_rc_add {
    echo "#!/bin/bash"
    echo ""

    case "$BUILDOPT" in
    0|1)
    ;;
    2|3)
        if [ "$1" == "dom0" ]; then
            echo "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
            echo "iptables -t nat -A PREROUTING -p tcp --dport 222 -j DNAT --to-destination 10.123.123.2:22"
            echo "echo \"1\" > /proc/sys/net/ipv4/ip_forward"
            echo ""
        fi

        echo "DNSS=\`dmesg | grep nameserver0\`"
        echo "if [ \$? -eq 0 ]; then"
        echo "    read -r _ _ DNS0 <<< \"\$DNSS\""
        echo "    DNS0=\${DNS0##*nameserver0=}"
        echo "    DNS0=\${DNS0%%,*}"
        echo "else"
        echo "    DNS0=${RASPDNS}"
        echo "fi"
        echo ""
        echo "echo \"nameserver \$DNS0\" > /etc/resolv.conf"
    ;;
    *)
        echo "Invalid BUILDOPT setting" >&2
        exit 1
    ;;
    esac
}

function inittab {
    case "$1" in
    dom0)
        case "$HYPERVISOR" in
        KVM)
            cat configs/inittab.kvm
        ;;
        *)
            cat configs/inittab.dom0
        ;;
        esac
    ;;
    domu)
        cat configs/inittab.domu
    ;;
    *)
        echo "Invalid inittab option" >&2
        exit 2
    ;;
    esac
}

function config_txt {
    case "$HYPERVISOR" in
    KVM)
        cat configs/config_kvm.txt
    ;;
    *)
        cat configs/config_xen.txt
    ;;
    esac
}