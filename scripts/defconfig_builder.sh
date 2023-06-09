#!/bin/bash
#
#  defconfig_builder.sh
#
#  Copyright (C) 2015 Texas Instruments Incorporated - http://www.ti.com/
#  ALL RIGHTS RESERVED
#
#  This script will perform a merge of config fragment files into a defconfig
#  based on a map file.  The map file defines the defconfig options that have
#  been tested to boot and compile.
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  For more information type defconfig_builder.sh -?
#

DEBUG_CONFIG_TAG="debug_options"
CONFIG_FRAGMENT_TAG="config-fragment="
DISCLAIMER="\n*Please be advised that the Debug Option defconfigs may\nimpact \
performance and should only be used for debugging.\n"

# Template for temporary build files.. use PID to differentiate
TMP_PREFIX=ti_defconfig_builder_$$
TMP_TEMPLATE="$TMP_PREFIX"_XXXXX.tmp

set_working_directory() {
	SCRIPT_PATH=$(readlink -f $(dirname "${BASH_SOURCE[0]}"))

	if [ ! -v KERNEL_PATH ]; then
		if [ -f $(pwd)/MAINTAINERS ]; then
			KERNEL_PATH=$(pwd)
		else
			KERNEL_PATH=$SCRIPT_PATH/../linux/
		fi
	fi

	KERNEL_PATH=$(readlink -f $KERNEL_PATH)

	if [ ! -f $KERNEL_PATH/MAINTAINERS ]; then
		echo "Error: $KERNEL_PATH does not look like a kernel directory"
		exit 1
	fi
}

prepare_for_exit() {
	D=$(dirname "$PROCESSOR_FILE")
	rm -f "$PROCESSOR_FILE"
	rm -f "$BUILD_TYPE_FILE"
	rm -f "$TEMP_TYPE_FILE"
	if [ -s "$OLD_CONFIG" ]; then
		mv "$OLD_CONFIG" "$KERNEL_PATH"/.config
	fi
	# Clean everyone else up if we missed any
	rm -f "$D"/"$TMP_PREFIX"*.tmp
	exit
}

check_for_config_existance() {
	# Check to make sure that the config fragments exist
	TEMP_EXTRA_CONFIG_FILE=$(echo "$BUILD_DETAILS" | cut -d: -f6)
	if [ -z "$TEMP_EXTRA_CONFIG_FILE" ]; then
		CONFIG_FRAGMENTS=
	else
		for CONFIG_FRAGMENT_FILE in $TEMP_EXTRA_CONFIG_FILE;
		do
			# If we do already point to existing file, we are good.
			if [ -e "$CONFIG_FRAGMENT_FILE" ]; then
				CONFIG_FRAG="$CONFIG_FRAGMENT_FILE"
			else
				# Assume it is present in working path
				CONFIG_FRAG="$FRAGMENTS_PATH/$CONFIG_FRAGMENT_FILE"
			fi
			if [ ! -e "$CONFIG_FRAG" ]; then
				CONFIG_FRAGMENTS="N/A"
			fi
		done
	fi

	if ! grep -qc "$BT_TEMP" "$BUILD_TYPE_FILE"; then
		# If the config file and config fragments are available
		# add it to the list.
		CONFIG_FILE=$(echo "$BUILD_DETAILS" | awk '{print$8}')
		if [ "$CONFIG_FILE" = "None" ]; then
			CONFIG_FILE=
		else
			if [ -e "$SCRIPT_PATH""/""$CONFIG_FILE" ]; then
				CONFIG_FILE=
			fi
		fi
		# If the check for the config file and the config fragments
		# pass then these two variables should be empty.  If
		# they fail then they should be N/A.
		if [ -z "$CONFIG_FILE" -a -z "$CONFIG_FRAGMENTS" ]; then
			max_configs=$((max_configs+1))
			echo -e '\t'"$max_configs". "$BT_TEMP" >> "$BUILD_TYPE_FILE"
		fi
	fi
}

choose_build_type() {
	TEMP_BT_FILE=$(mktemp -t $TMP_TEMPLATE)
	TEMP_BUILD_FILE=$(mktemp -t $TMP_TEMPLATE)

	grep "$DEFCONFIG_FILTER" "$DEFCONFIG_MAP_FILE" | grep "^classification:" | awk '{print$4}' > "$TEMP_BUILD_FILE"

	max_configs=0
	while true;
	do
		CONFIG_FILE=
		CONFIG_FRAGMENTS=

		BT_TEMP=$(head -n 1 "$TEMP_BUILD_FILE")
		if [ -z "$BT_TEMP" ]; then
			break
		fi
		BUILD_DETAILS=$(grep -w "$BT_TEMP" "$DEFCONFIG_MAP_FILE")
		check_for_config_existance
		sed -i "1d" "$TEMP_BUILD_FILE"
	done

	NUM_OF_BUILDS=$(wc -l "$BUILD_TYPE_FILE" | awk '{print$1}')
	if [ "$NUM_OF_BUILDS" -eq 0 ]; then
		echo "Sorry no build targets for this configuration.  Are you on the right branch?"
		prepare_for_exit
	fi

	# Force the user to answer.  Maybe the user does not want to continue
	while true;
	do
		echo -e "Available ""$DEFCONFIG_FILTER"" defconfig build options:\n"
		cat "$BUILD_TYPE_FILE"
		echo ""
		read -p "Please enter the number of the defconfig to build or 'q' to exit: " REPLY

		if [ "$REPLY" = "q" -o "$REPLY" = "Q" ]; then
			prepare_for_exit
		elif ! [[ "$REPLY" =~ ^[0-9]+$ ]]; then
			echo -e "\n$REPLY is not a number of the defconfig.  Please try again!\n"
			continue
		elif [ "$REPLY" -gt '0' -a "$REPLY" -le "$NUM_OF_BUILDS" ]; then
			CHOSEN_BUILD_TYPE=$(grep -w "$REPLY" "$BUILD_TYPE_FILE" | awk '{print$2}')
			break
		else
			echo -e "\n'$REPLY' is not a valid choice. Please \
choose a value between '1' and '$max_configs':\n"
		fi
	done
	rm "$TEMP_BT_FILE"
	rm "$TEMP_BUILD_FILE"
}

list_all_targets() {

	TMP_MAP=$(mktemp -t $TMP_TEMPLATE)

	count=0
	max_types=0
	while [ "x${SUPPORTED_ARCH[max_types]}" != "x" ]
	do
		DEFCONFIG_MAP_FILE=${SUPPORTED_ARCH[(count * 3) + 2]}
		count=$(( $count + 1 ))
		max_types=$(( $max_types + 3 ))
		if [ ! -e "$DEFCONFIG_MAP_FILE" ]; then
			continue
		fi

		cat "$DEFCONFIG_MAP_FILE" > "$TMP_MAP"
		while true;
		do
			CONFIG_FILE=
			CONFIG_FRAGMENTS=

			BT_TEMP=$(head -n 1 "$TMP_MAP" | awk '{print$4}')
			BUILD_DETAILS=$(head -n 1 "$TMP_MAP")
			if [ -z "$BUILD_DETAILS" ]; then
				break
			fi
			check_for_config_existance
			sed -i "1d" "$TMP_MAP"
		done
		rm "$TMP_MAP"
	done
	cat "$BUILD_TYPE_FILE"
}

get_build_details() {
	count=0
	max_types=0
	while [ "x${SUPPORTED_ARCH[max_types]}" != "x" ]
	do
		DEFCONFIG_MAP_FILE=${SUPPORTED_ARCH[(count * 3) + 2]}
		if [ -e "$DEFCONFIG_MAP_FILE" ]; then
			BUILD_DETAILS=$(grep -w "$CHOSEN_BUILD_TYPE" "$DEFCONFIG_MAP_FILE")
			if [ ! -z "$BUILD_DETAILS" ]; then
				if [ -z ${DEFCONFIG_KERNEL_PATH} ]; then
					DEFCONFIG_KERNEL_PATH=${SUPPORTED_ARCH[(count * 3) + 1]}
				fi
				break
			fi
		fi

		count=$(( $count + 1 ))
		max_types=$(( $max_types + 3 ))
	done

	if [ -z "$BUILD_DETAILS" ]; then
		echo "Cannot find the build type or a match for $CHOSEN_BUILD_TYPE"
		TEMP_BUILD_FILE=$(mktemp -t $TMP_TEMPLATE)
		grep "$CHOSEN_BUILD_TYPE" "$DEFCONFIG_MAP_FILE" > "$TEMP_BUILD_FILE"
		while true;
		do
			CONFIG_FILE=
			CONFIG_FRAGMENTS=

			BT_TEMP=$(head -n 1 "$TEMP_BUILD_FILE" | awk '{print$4}')
			if [ -z "$BT_TEMP" ]; then
				break
			fi
			BUILD_DETAILS=$(grep -w "$BT_TEMP" "$DEFCONFIG_MAP_FILE")
			check_for_config_existance
			sed -i "1d" "$TEMP_BUILD_FILE"
		done
		rm -rf "$TEMP_BUILD_FILE"

		NUM_OF_BUILDS=$(wc -l "$BUILD_TYPE_FILE" | awk '{print$1}')
		if [ "$NUM_OF_BUILDS" -eq 0 ]; then
			echo "Maybe try one of the following:"
			list_all_targets
		else
			echo "Did you mean any of the following?"
			cat "$BUILD_TYPE_FILE"
		fi

		return 1
	fi

	DEFCONFIG=$(echo "$BUILD_DETAILS" | awk '{print$6}')
	DEFCONFIG="$DEFCONFIG_KERNEL_PATH""/""$DEFCONFIG"
	CONFIG_FILE=$(echo "$BUILD_DETAILS" | awk '{print$8}')
	# There may be a need to just build with the config fragments themselves
	if [ "$CONFIG_FILE" = "None" ]; then
		CONFIG_FILE=
	fi

	if [ ! -e "$SCRIPT_PATH/$CONFIG_FILE" ]; then
		echo "$SCRIPT_PATH/$CONFIG_FILE does not exist"
		return 1
	fi

	TEMP_EXTRA_CONFIG_FILE=$(echo "$BUILD_DETAILS" | cut -d: -f6)
	for CONFIG_FRAGMENT_FILE in $TEMP_EXTRA_CONFIG_FILE;
	do
		# If we do already point to existing file, we are good.
		if [ -e "$CONFIG_FRAGMENT_FILE" ]; then
			CONFIG_FRAG="$CONFIG_FRAGMENT_FILE"
		else
			# Assume it is present in working path
			CONFIG_FRAG="$FRAGMENTS_PATH/$CONFIG_FRAGMENT_FILE"
		fi
		if [ -e "$CONFIG_FRAG" ]; then
			EXTRA_CONFIG_FILE="$EXTRA_CONFIG_FILE $CONFIG_FRAG"
		else
			echo "$CONFIG_FRAG" does not exist
		fi
	done
}

build_defconfig() {

	if [ ! -z "$CONFIG_FILE" -a -e "$SCRIPT_PATH/$CONFIG_FILE" ]; then
		CONFIGS=$(grep "$CONFIG_FRAGMENT_TAG" "$SCRIPT_PATH/$CONFIG_FILE" | cut -d= -f2)
	fi

	"$KERNEL_PATH"/scripts/kconfig/merge_config.sh -m -r "$DEFCONFIG" \
		"$CONFIGS" "$EXTRA_CONFIG_FILE" > /dev/null

	if [ "$?" = "0" ];then
		if [ -z ${DEFCONFIG_OUT} ]; then
			echo "Creating defconfig file ""$DEFCONFIG_KERNEL_PATH/""$CHOSEN_BUILD_TYPE"_defconfig
			mv .config "$DEFCONFIG_KERNEL_PATH"/"$CHOSEN_BUILD_TYPE"_defconfig
		else
			if [ ! -d ${DEFCONFIG_OUT} ]; then
				mkdir -p ${DEFCONFIG_OUT}
			fi
			echo "Creating defconfig file ""$DEFCONFIG_OUT/""$CHOSEN_BUILD_TYPE"_defconfig
			mv .config ${DEFCONFIG_OUT}/${CHOSEN_BUILD_TYPE}_defconfig
		fi
	else
		echo "Defconfig creation failed"
		return 1
	fi
}

choose_defconfig_type() {

	TEMP_TYPE_FILE=$(mktemp -t $TMP_TEMPLATE)

	TYPE_FILE=$(grep -v "#" "$DEFCONFIG_MAP_FILE" | awk '{print$2}' | sort -u)

	max_types=0
	for TYPE_TMP in $TYPE_FILE;
	do
		max_types=$((max_types+1))
		echo -e '\t' "$max_types." "$TYPE_TMP" >> "$TEMP_TYPE_FILE"
	done
	echo >> "$TEMP_TYPE_FILE"

	while true;
	do
		cat "$TEMP_TYPE_FILE"
		read -p "Please choose a defconfig type to build for or 'q' to exit: " REPLY
		if [ "$REPLY" = "q" -o "$REPLY" = "Q" ]; then
			prepare_for_exit
		elif ! [[ "$REPLY" =~ ^[0-9]+$ ]]; then
			echo -e "\n'$REPLY' is not a number for the build type.  Please try again!\n"
			continue
		elif [ "$REPLY" -gt '0' -a "$REPLY" -le "$max_types" ]; then
			REPLY="$REPLY""."
			DEFCONFIG_FILTER=$(awk '{if ($1 == "'"$REPLY"'") print $2;}' "$TEMP_TYPE_FILE")
			break
		else
			echo -e "\n'$REPLY' is not a valid choice. Please \
choose a value between '1' and '$max_types':\n"
		fi
	done

	DEBUG_BUILD=$(grep "$DEFCONFIG_FILTER" "$DEFCONFIG_MAP_FILE" | grep -wc "$DEBUG_CONFIG_TAG" )
	if [ "$DEBUG_BUILD" -gt '0' ]; then
		echo -e "$DISCLAIMER"
	fi
}

choose_architecture() {

	TEMP_ARCH_FILE=$(mktemp -t $TMP_TEMPLATE)

	max_types=0
	count=0
	while [ "x${SUPPORTED_ARCH[max_types]}" != "x" ]
	do
		ARCH_TYPE=${SUPPORTED_ARCH[max_types]}
		if [ -e "${SUPPORTED_ARCH[max_types + 2]}" ]; then
			count=$(( $count + 1 ))
			echo -e '\t' "$count." "$ARCH_TYPE" >> "$TEMP_ARCH_FILE"
		fi
		max_types=$(( $max_types + 3 ))
	done

	if [ "$count" -eq 1 ]; then
		REPLY=$count
	else
		while true;
		do
			cat "$TEMP_ARCH_FILE"
			read -p "Please choose an architecture to build for or 'q' to exit: " REPLY
			if [ "$REPLY" = "q" -o "$REPLY" = "Q" ]; then
				prepare_for_exit
			elif ! [[ "$REPLY" =~ ^[0-9]+$ ]]; then
				echo -e "\n'$REPLY' is not a number for the build type.  Please try again!\n"
				continue
			elif [ "$REPLY" -gt '0' -a "$REPLY" -le "$max_types" ]; then
				REPLY_DISP="$REPLY""."
				ARCH_TO_BUILD=$(awk '{if ($1 == "'"$REPLY_DISP"'") print $2;}' "$TEMP_ARCH_FILE")
				# System test configs are specific and contain
				# the v7 and v8 tags so we have to do something
				# special.
				if [ ${ARCH_TO_BUILD} == "System" ]; then
					SYSTEM_TEST_ARCH=$(awk '{if ($1 == "'"$REPLY_DISP"'") print $4;}' "$TEMP_ARCH_FILE")
					ARCH_TEST="System Test "${SYSTEM_TEST_ARCH}
				else
					ARCH_TEST=${ARCH_TO_BUILD}
				fi
				break
			else
				echo -e "\n'$REPLY' is not a valid choice. Please \
	choose a value between '1' and '$max_types':\n"
			fi
		done
	fi

	max_types=0
	while [ "x${SUPPORTED_ARCH[max_types]}" != "x" ]
	do
		ARCH_TYPE=${SUPPORTED_ARCH[max_types]}
		ARCH_COUNTER=$(grep -c "$ARCH_TEST" <<< $ARCH_TYPE)
		if [ "$ARCH_COUNTER" -gt 0 ]; then
			break
		fi
		max_types=$(( $max_types + 3 ))
	done

	DEFCONFIG_KERNEL_PATH=${SUPPORTED_ARCH[max_types + 1]}
	DEFCONFIG_MAP_FILE=${SUPPORTED_ARCH[max_types + 2]}
}

usage() {
cat << EOF

This script will perform a merge of config fragment files into a defconfig
based on a map file.  The map file defines the defconfig options that have
been tested to boot and compile.

Optional:
	-k - Location of the Linux kernel source
	-w - Same as -k (deprecated)
	-t - Indicates the type of defconfig to build.  This will force the
	     defconfig to build without user interaction.
	-l - List all buildable defconfig options
	-o - Outputs the built defconfigs to a different directory.

Command line example to generate the SDK Raspberry PI4 processor defconfig
automatically without user interaction:

	config_fragments/defconfig_builder.sh -t sdk_raspi4_release

Command line Example if building from the config_fragments directory:
	defconfig_builder.sh -w ../.

User interactive command line example:
	config_fragments/defconfig_builder.sh
EOF
}

#########################################
# Script Start
#########################################
while getopts "?f:?k:?m:w:t:o:l" OPTION
do
	case $OPTION in
		f)
			FRAGMENTS_PATH=$OPTARG;;
		k|w)
			KERNEL_PATH=$OPTARG;;
		t)
			CHOSEN_BUILD_TYPE=$OPTARG;;
		l)
			LIST_TARGETS="y";;
		m)
			MAPS_PATH=$OPTARG;;
		o)
			DEFCONFIG_OUT=$OPTARG;;
		?)
			usage
			exit;;
     esac
done

trap prepare_for_exit SIGHUP EXIT SIGINT SIGTERM

set_working_directory

if [ -z ${FRAGMENTS_PATH+x} ]; then
    FRAGMENTS_PATH=$SCRIPT_PATH
fi

if [ -z ${MAPS_PATH+x} ]; then
    MAPS_PATH=$SCRIPT_PATH
fi

SUPPORTED_ARCH=(
"v8 ARM Architecture" "$KERNEL_PATH/arch/arm64/configs" "$MAPS_PATH/defconfig_map.txt"
"x86 Architecture" "$KERNEL_PATH/arch/x86/configs" "$MAPS_PATH/x86_defconfig_map.txt")

BUILD_TYPE_FILE=$(mktemp -t $TMP_TEMPLATE)

if [ ! -z "$LIST_TARGETS" ]; then
	echo "The following are a list of buildable defconfigs:"
	list_all_targets
	exit 0
fi


PROCESSOR_FILE=$(mktemp -t $TMP_TEMPLATE)
OLD_CONFIG=$(mktemp -t $TMP_TEMPLATE)
if [ -f "$KERNEL_PATH"/.config ]; then
	mv "$KERNEL_PATH"/.config "$OLD_CONFIG"
fi

if [ ! -z "$CHOSEN_BUILD_TYPE" ]; then
	get_build_details
	if [ "$?" -gt 0 ]; then
		exit 1
	fi

	build_defconfig
	if [ "$?" -gt 0 ]; then
		exit 1
	fi
	exit 0
fi

choose_architecture

if [ ! -e "$DEFCONFIG_MAP_FILE" ]; then
	echo "No defconfig map file found"
	exit 1
fi

choose_defconfig_type
choose_build_type
get_build_details

build_defconfig
