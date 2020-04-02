# Firecracker initrd creator
Create a initrd to be used as the Firecracker guest VM, based on Alpine

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
    -k             Create an inirtd image from an existing rootfs at ./build/rootfs
    -z             Compress the initrd using gzip
    --minimal      Create a minimal image without networking
```

Build artifacts are placed inside `./build`

A few words about the `-k` option:
1. Invoke the took as usual to create a stock initrd. This will leave a rootfs
in ./build/rootfs.
2. The rootfs can be customized as desired.
3. Use the `-k` option to compress the customized rootfs.

## TODO
Allow creating initrd for other distros.
