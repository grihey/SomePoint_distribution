#!/bin/bash

set -x

. config

FILE=tester_was_here

eval ${SSH} ls ${FILE}
ret=$?

# File should not exist
if [ "$ret" == "0" ]; then
    exit 1
fi

eval ${SSH} touch ${FILE}
ret=$?

echo "return: $ret"
if [ "$ret" != "0" ]; then
    echo "Failed touch file"
    exit 1
fi

# Test fails if we get here
exit 0