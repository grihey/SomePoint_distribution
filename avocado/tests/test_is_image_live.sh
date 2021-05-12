#!/bin/bash

. config

eval ${SSH} echo "hello"
ret=$?

echo "return: $ret"
exit $ret

