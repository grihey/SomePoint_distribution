#!/bin/bash

# Get actual directory of this bash script
SDIR="$(dirname "${BASH_SOURCE[0]}")"
SDIR="$(realpath "$SDIR")"

if [ -z ${IMAGE} ]; then
    IMAGE="${SDIR}/../buildroot/output/images/rootfs-withdomu.ext2"
fi

IMAGE_DIR="$(dirname "${IMAGE}")"
IMAGE_DIR="$(realpath "$IMAGE_DIR")"

RESULTS=$(mktemp)

if [ -z ${ID_RSA} ]; then
    ID_RSA=${SDIR}/../images/device_id_rsa
fi

TESTS_DIR=${SDIR}/../avocado/tests
TMP_CONFIG=${TESTS_DIR}/tmp_config
TMP_LOG=$(mktemp)

# Populate tmp config
function Append_tmp_config_file {
    echo $1 >> ${TMP_CONFIG}
}

function Remove_tmp_config {
    if [ -f ${TMP_CONFIG} ]; then
        rm ${TMP_CONFIG}
    fi
}

Remove_tmp_config
Append_tmp_config_file "IMAGE_DIR=${IMAGE_DIR}"
Append_tmp_config_file "IMAGE=${IMAGE}"
Append_tmp_config_file "ID_RSA=${ID_RSA}"


PORT=2222
# Serial-only & snapshot of the image
${SDIR}/../run_x86_qemu.sh -s -ss -p1 ${PORT} -i ${IMAGE} & #&> ${TMP_LOG} &
QEMU_PID=$!
echo "Qemu PID: ${QEMU_PID}"

# Remove old known key
ssh-keygen -R "[localhost]:2222" &>2 /dev/null

echo "Waiting for VM to start"
for i in  {1..10}; do
    printf "."
    sleep 1
    ret=`ssh -i ${ID_RSA} root@localhost -o StrictHostKeyChecking=accept-new -p ${PORT} echo "hello"`
    if [ "${ret}" == "hello" ]; then
        break
    fi
    if [ "${i}" == "10" ]; then
        echo "Not able to connect VM. Exiting."
        exit 1
    fi
done
echo ""
echo "VM running"

# Clean up before exit
function cleanup {
    # Shutdown VM
    echo "Shutting down VM"
    ${SDIR}/../stop_x86_qemu.sh ${IMAGE_DIR} ${PORT} ${ID_RSA} ${QEMU_PID}
    Remove_tmp_config
    rm ${RESULTS}
    rm ${TMP_LOG}
}
trap cleanup EXIT
trap cleanup TERM

# Declare test commands
declare -a arr=( \
    "cd ${TESTS_DIR} && avocado run --job-timeout 60 test_* --tap ${RESULTS} &"
)

for (( i = 0; i < ${#arr[@]} ; i++ )); do
    printf "\n      Running: ${arr[$i]}\n\n"

    # Run each command in array
    eval "${PASS_ENV} ${arr[$i]}"
    pids[${i}]=$!
done

# wait for all pids
for pid in ${pids[*]}; do
    wait $pid
done

echo "Result file ${RESULTS}"
cat ${RESULTS}
ret=$(grep -e "not ok" -e "SKIP Test" ${RESULTS})

if [ "${ret}" ]; then
    echo "Test failed"
    exit 1
fi

echo "All tests pass"
exit 0
