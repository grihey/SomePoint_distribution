#!/bin/bash

iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
echo "1" > /proc/sys/net/ipv4/ip_forward

#killall -SIGUSR2 udhcpc # release your existing DHCP lease
brctl addbr xenbr0 # create a new bridge called “xenbr0”
brctl addif xenbr0 eth0 # put eth0 onto xenbr0
#killall udhcpc # terminate the DHCP client daemon
#udhcpc -R -b -p /var/run/udhcpc.xenbr0.pid -i xenbr0 # restart the DHCP client daemon on the new bridge
