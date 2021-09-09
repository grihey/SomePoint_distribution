#!/bin/bash

set -e

BOARD_DIR="$(dirname $0)"
BOARD_NAME="$(basename ${BOARD_DIR})"
GENIMAGE_CFG="${BOARD_DIR}/genimage-${BOARD_NAME}.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# copy board specific config.txt as baseline
cp -f "${TCDIST_DIR}"/configs/board/"$BOARD_NAME"/config.txt "${BINARIES_DIR}/rpi-firmware/config.txt"

# copy linux build overlay files to boot partition overlay.  rpi-firmware versions are not in sync.
cp -f "${BASE_DIR}"/build/linux-"${TCDIST_LINUX_BRANCH}"/arch/arm/boot/dts/overlays/*.dtbo \
          "${BINARIES_DIR}/rpi-firmware/overlays/"

for arg in "$@"
do
	case "${arg}" in
		--add-miniuart-bt-overlay)
		if ! grep -qE '^dtoverlay=' "${BINARIES_DIR}/rpi-firmware/config.txt"; then
			echo "Adding 'dtoverlay=miniuart-bt' to config.txt (fixes ttyAMA0 serial console)."
			cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"
# fixes rpi (3B, 3B+, 3A+, 4B and Zero W) ttyAMA0 serial console
dtoverlay=miniuart-bt,krnbt=on
__EOF__
		fi
		;;
		--aarch64)
		# Run a 64bits kernel (armv8)
		sed -e '/^kernel=/s,=.*,=Image,' -i "${BINARIES_DIR}/rpi-firmware/config.txt"
		if ! grep -qE '^arm_64bit=1' "${BINARIES_DIR}/rpi-firmware/config.txt"; then
			cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"
# enable 64bits support
arm_64bit=1
__EOF__
		fi
		;;
		--gpu_mem_256=*|--gpu_mem_512=*|--gpu_mem_1024=*)
		# Set GPU memory
		gpu_mem="${arg:2}"
		sed -e "/^${gpu_mem%=*}=/s,=.*,=${gpu_mem##*=}," -i "${BINARIES_DIR}/rpi-firmware/config.txt"
		;;
	esac

done

# overwrites buildroot/package/rpi-firmware version of cmdline.txt:
if [ -f "${BINARIES_DIR}/rpi-firmware/cmdline.txt" ] && [ -f "${TCDIST_DIR}/br_secure/arm64_cm4io_kvm_guest_secure_release_defconfig" ]; then
	echo "Change Kernel cmdline to match cm4io defconfig."
	cmdline=$(sed -n -e 's/^CONFIG_CMDLINE="\(.*\)"/\1/p' "${TCDIST_DIR}"/br_secure/arm64_cm4io_kvm_guest_secure_release_defconfig)
	cat << __EOF__ > "${BINARIES_DIR}/rpi-firmware/cmdline.txt"
$cmdline
__EOF__
fi

# Pass an empty rootpath. genimage makes a full copy of the given rootpath to
# ${GENIMAGE_TMP}/root so passing TARGET_DIR would be a waste of time and disk
# space. We don't rely on genimage to build the rootfs image, just to insert a
# pre-built one in the disk image.

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

rm -rf "${GENIMAGE_TMP}"

genimage \
	--rootpath "${ROOTPATH_TMP}"   \
	--tmppath "${GENIMAGE_TMP}"    \
	--inputpath "${BINARIES_DIR}"  \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"

exit $?


