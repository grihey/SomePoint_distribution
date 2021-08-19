#!/bin/bash
# Generates random sequential qemu/kvm macs

. ./helpers.sh
Load_config

if [ "$1" == "check_script" ]; then
    Shellcheck_bashate ./genmacs.sh ./helpers.sh ${TCDIST_OUTPUT}/.setup_sh_config_${TCDIST_PRODUCT}
    exit
fi

count=$(wc -w <<< "${TCDIST_VMLIST}")
count=$((count + 1))

# Seed randoms with current unix time in milliseconds
RANDOM=$(date +%s)

# Qemu/kvm mac header
macstr="52:54:00:"

# Add couple of random octets
macstr+="$(printf "%02X:" $((RANDOM % 256)))"
macstr+="$(printf "%02X:" $((RANDOM % 256)))"

# Random last octet
lastoct="$((RANDOM % 256))"

i=0
while [ $i -lt "$count" ]; do
    # Print seqential macs (We don't care about wrapping here, e.g. if first mac ends with FF next will end with 00)
    printf "%s%02X\n" "$macstr" $(((lastoct + i) % 256))
    i=$((i + 1))
done
