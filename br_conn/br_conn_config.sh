#!/bin/bash

function Interfaces {
    echo "auto lo"
    echo "iface lo inet loopback"
    echo ""
    echo "auto eth0"
    echo "iface eth0 inet dhcp"
    echo ""
    echo "iface eth1 inet manual"
    echo ""
    echo "iface default inet dhcp"
}
