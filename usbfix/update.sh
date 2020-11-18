#!/bin/bash

FWREPO="https://github.com/raspberrypi/firmware"

pushd "${0%/*}"

if [ -d firmware ]; then
  cd firmware
  git pull
  cd ..
else
  git clone --depth 1 $FWREPO
fi

cp -f firmware/boot/start4.elf firmware/boot/fixup4.dat .

popd
