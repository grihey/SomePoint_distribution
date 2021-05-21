#!/bin/bash

# Include generic rootfs adjustments
. ../adjust_rootfs.sh -hostname -interfaces "$@"

# Insert vm specific adjustments here
set -x
e2cp -P 755 -O 0 -G 0 vmctl.sh "${2}:/root"
e2cp -P 755 -O 0 -G 0 ../br_conn/vm_1.sh "${2}:/root"
e2cp -P 755 -O 0 -G 0 ../br_conn/br_conn.bzImage "${2}:/root"
e2cp -P 755 -O 0 -G 0 ../br_conn/br_conn.ext2 "${2}:/root"
