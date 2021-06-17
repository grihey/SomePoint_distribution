#!/bin/bash
sock=$(find /tmp/ -name "*serial*")
if [ "$sock" = "" ] ; then
    echo "Not found."
    exit
fi

socat UNIX-CONNECT:"$sock" -
