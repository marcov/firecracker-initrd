# Firecracker initrd creator

Create a initrd to be used as the Firecracker guest VM, based on Alpine or openSUSE distro.

## Requirements
Builds are done inside a container, so you need to have Podman or Docker installed.

Root permissions are not needed, this can run on rootless Podman / Docker.

## Usage
```
./build.sh [options] [DISTRO-FLAVOR]

Create a initrd based on the specified distro flavor: alpine or suse.
If not specified, the alpine distro is used.

Options:

    -h             Show this help

    -k             Only Compress a previously created rootfs into an initrd image
```

Build artifacts are placed inside `./build`

