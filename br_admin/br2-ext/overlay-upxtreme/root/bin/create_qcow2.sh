#!/bin/bash

function Help {
    echo "Usage:"
    echo "$0 <qcow2_file_system_name>"
}

if [ -z "$1" ];
then
    echo "qcow2 file name missing"
    Help
    exit 1
fi

if [ -f "$1" ];
then
    echo "$1 file exists"
    Help
    exit 1
fi

qemu-img create -f qcow2 $1 50G
