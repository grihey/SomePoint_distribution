#!/bin/sh
guest="CustomLinux"

ip link add virbr0 type bridge
ifconfig virbr0 10.0.3.15 netmask 255.255.255.0 up
avocado run type_specific.io-github-autotest-qemu.migrate.default.tcp --vt-type qemu --vt-guest-os $guest
ip link set virbr0 down
ip link del virbr0
