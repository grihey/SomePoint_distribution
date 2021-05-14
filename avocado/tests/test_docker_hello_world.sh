#!/bin/bash

. config

set -x

eval ${SSH} docker run hello-world
ret=$?

echo "return: $ret"
exit $ret

