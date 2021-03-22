#!/bin/bash

case "$1" in
build)
    docker build -f Dockerfile . -t avocado-setup:latest
;;
shell)
    docker run --privileged -it --rm -v "${PWD}:/../data" --entrypoint=/bin/bash avocado-setup
;;
export)
    docker create --name avocado-export-tmp avocado-setup
    docker cp avocado-export-tmp:/avocado-vt-bootstrap.tar.gz ../images/
    docker rm -f avocado-export-tmp
;;
clean)
    docker image rm -f avocado-setup
;;
*)
    echo "docker.sh: bad option $1"
    exit 1
;;
esac
