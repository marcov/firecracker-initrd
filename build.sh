#!/bin/sh
#
# (C) 2019 SUSE LLC
# Create a Alpine or openSUSE based initrd to be used with Firecracker VMM
#

set -euo pipefail

buildDir=`pwd`/build
rootfsDir=${buildDir}/rootfs
builder="/build-initrd-in-ctr.sh"

if command -v podman >/dev/null; then
	ctrEngine=podman
elif command -v docker >/dev/null; then
	ctrEngine=docker
else
	echo "ERROR: Podman or Docker is required!"
	exit 127
fi

mkdir -p $buildDir

$ctrEngine run \
	-it --rm \
	-v${buildDir}:/build \
	-v`pwd`/container:/container:ro \
	-v`pwd`/container/${builder}:${builder}:ro \
	-v`pwd`/guest:/guest:ro \
	alpine:latest \
	${builder} $@

