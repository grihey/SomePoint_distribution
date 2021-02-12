#!/bin/bash

IMAGE=$1
LOCALIP=`ip a s eth0 | grep "inet " | cut -d" " -f6 | cut -d"/" -f1`
USER=$(whoami)
PORT=222
VDAGENT="-device virtio-serial-pci -device virtserialport"

[ -z "$LOCALIP" ] && LOCALIP="127.0.0.1"
[ -z "$QEMUDIR" ] && QEMUDIR="./"
[ -z "$MACHINE" ] && MACHINE="virt"
[ -z "$CPUTYPE" ] && CPUTYPE="host"
[ -z "$AUDIO" ] && AUDIO=""
[ -z "$KERNEL" ] && KERNEL="Image"
[ -z "$PORT" ] && PORT=$((2000 + RANDOM % 1000))
[ -z "$NET" ] && NETOPTS="-nic user,id=net0,host=10.123.123.1,net=10.123.123.0/24,restrict=off,hostname=guest,hostfwd=tcp:$LOCALIP:$PORT-10.123.123.2:22"
[ -z "$MEM" ] && MEM=2560
[ -z "$SMP" ] && SMP="-smp 2"
[ -z "$SCREEN" ] && SCREEN="-nographic -device virtio-gpu-pci $VDAGENT"
[ -n "$DEBUG" ] && DEBUGOPTS="-S -s"
[ -n "$PROFILE" ] && PROFILE="pmu=on"
[ -z "$PROFILE" ] && PROFILE="pmu=off"

if [ "$USER" = "root" ]; then
	[ ! -d /dev/net ] && mkdir /dev/net
	[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 0666 /dev/net/tun
fi

KERNEL_OPTS="root=/dev/vda console=ttyAMA0 nokaslr loglevel=8 rw ${SYSTEMD_DEBUG}"
USB="-device qemu-xhci -device usb-kbd -device usb-tablet"
DRIVE="-drive file=$IMAGE,format=raw,if=none,id=ubu-sd -device virtio-blk-device,drive=ubu-sd"
QEMUOPTS="-enable-kvm -cpu ${CPUTYPE},${PROFILE} ${SMP} -M ${MACHINE},virtualization=off,secure=off,highmem=off -m ${MEM} ${DEBUGOPTS} ${NETOPTS} ${AUDIO}"

echo "Running $QEMUDIR/qemu-system-aarch64 as user $USER"
echo "- Guest ssh access available at $LOCALIP:$PORT"
echo "- Spice server at '$SPICESOCK'"
echo "- Host wlan ip $LOCALIP"
echo "- $PROFILE"

$QEMUDIR/qemu-system-aarch64 \
	-kernel $KERNEL \
	$DTB $USB \
	$DRIVE $SCREEN \
	-append "$KERNEL_OPTS" \
	$QEMUOPTS
