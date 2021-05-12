#!/bin/bash

IMAGES=$1
PORT=$2
ID_RSA=$3
QEMU_PID=$4

if ! [ -z ${ID_RSA} ] && [ -f ${ID_RSA} ]; then
    ssh -i ${ID_RSA} root@localhost -p ${PORT} -o StrictHostKeyChecking=accept-new poweroff
    sleep 2
else
    echo "Cannot find identity file: ${ID_RSA}. Using kill -9 ${QEMU_PID}"
    kill -9 ${QEMU_PID}
fi