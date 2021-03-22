################################################################################
# Base image

FROM ubuntu:focal

ARG DEBIAN_FRONTEND="noninteractive"

################################################################################
# Required tools

RUN apt-get update		\
 && apt-get -y -q upgrade	\
 && apt-get -y -q install	\
    python3 python3-pip tcpdump netcat iproute2 arping git \
 && apt-get clean

# Install avocado packages:
RUN pip3 install avocado-framework
RUN pip3 install avocado-framework-plugin-vt

# Configure avocado
COPY customlinux.cfg /usr/local/lib/python3.8/dist-packages/virttest/shared/cfg/guest-os/Linux/LinuxCustom/

# Create bootstrap
RUN avocado vt-bootstrap --vt-type qemu --vt-guest-os=CustomLinux

RUN rm -rf /var/lib/avocado/data/avocado-vt/virttest/test-providers.d/downloads/io-github-autotest-qemu/.git

RUN cd /var/lib/avocado/data/avocado-vt/ \
 && tar czf /avocado-vt-bootstrap.tar.gz *

#RUN tar -cvfz /data/avocado-vt-bootstrap.tar.gz /var/lib/avocado/data/avocado-vt/

#COPY avocado-vt-bootstrap.tar.gz
