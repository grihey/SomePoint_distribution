#!/bin/bash

PORT=666
. config

# Port doesn't exist
eval ${SSH} echo "hello"
ret=$?

echo "return: $ret"
# Test should fail
if [ "$ret" != "0" ]; then
    exit 0
fi

# Test fails if we get here
exit 1