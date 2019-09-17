#!/bin/sh
#
# (C) 2019 SUSE LLC
# Create a Alpine or openSUSE based initrd to be used with Firecracker VMM
#

set -euo pipefail

buildDir=/build
rootfsDir=${buildDir}/rootfs
keepRoot=
flavor=
fcnetPath="/usr/local/bin/fcnet-setup.sh"
initrdFile="initrd.gz"

is_a_container() {
	if [ -f /run/.containerenv ]; then
		true
	elif command -v systemd-detect-virt &>/dev/null && systemd-detect-virt -q -c; then
		true
	elif [ "$$" = "1" ]; then
		true
	else
		false
	fi
}

rootfs_suse() {
	[ -f "config.xml" ] || { echo "ERROR: need a config.xml!"; exit 127; }
	# populate rootfs
	kiwi system prepare --description=`pwd`/container --allow-existing-root --root "$rootfsDir"

	rm -f ${rootfsDir}/etc/systemd/system/getty.target.wants/getty@tty1.service
	ln -sf /usr/lib/systemd/system/getty@.service ${rootfsDir}/etc/systemd/system/getty.target.wants/getty@ttyS0.service
}

setup_alpine() {
	apk add openssh gzip gcc libc-dev
}

rootfs_alpine() {
	mkdir "${rootfsDir}"
	apk -X http://dl-5.alpinelinux.org/alpine/latest-stable/main -U --allow-untrusted --root ${rootfsDir} --initdb \
		add \
			alpine-base \
			iptables \
			iproute2 \
			openssh \
			util-linux \
			openrc \
			grep

	cd ${rootfsDir}
	ln -sf /etc/init.d/devfs  ./etc/runlevels/boot/devfs
	ln -sf /etc/init.d/procfs ./etc/runlevels/boot/procfs
	ln -sf /etc/init.d/sysfs  ./etc/runlevels/boot/sysfs

	ln -sf /etc/init.d/networking ./etc/runlevels/default/networking

	ln -sf /etc/init.d/agetty.ttyS0 ./etc/runlevels/default/agetty.ttyS0
	ln -sf agetty       ./etc/init.d/agetty.ttyS0

	ln -sf /etc/init.d/sshd.eth0 ./etc/runlevels/default/sshd.eth0
	ln -sf sshd      ./etc/init.d/sshd.eth0

	echo "ttyS0" >> ./etc/securetty

	cat >> ./etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
#        address 172.16.0.2
#        netmask 255.255.255.0
#        gateway 172.16.0.1
EOF

	cp ${fcnetPath} ./${fcnetPath}
	chown root ./${fcnetPath}
	chmod 755 ./${fcnetPath}

	cat >> ./etc/init.d/fcnet << EOF
#!/sbin/openrc-run

command="${fcnetPath}"
EOF
	ln -sf /etc/init.d/fcnet ./etc/runlevels/default/fcnet

	chmod 755 ./etc/init.d/fcnet

	local openrcInit="/sbin/openrc-init"

	mv ./sbin/init .${openrcInit}

	cat << EOF | gcc -x c - -static -o ./sbin/init
#include <sys/io.h>
#include <unistd.h>

static __inline void
outb_p (unsigned char __value, unsigned short int __port)
{
  __asm__ __volatile__ ("outb %b0,%w1\noutb %%al,\$0x80": :"a" (__value),
			"Nd" (__port));
}

int main(int argc, char *const argv[]) {
    iopl(3);
    outb_p(123, 0x03f0);
    return execv("${openrcInit}", argv);
}
EOF

	cd - >/dev/null
}

setup_ssh_key() {
	rm -rf ssh-key
	mkdir -p ssh-key
	ssh-keygen -f ssh-key/id_rsa -N ""
	mkdir -m 0600 -p ${rootfsDir}/root/.ssh/
	cp ssh-key/id_rsa.pub ${rootfsDir}/root/.ssh/authorized_keys
}

setup_ssh_insecure() {
	sed -E -i ${rootfsDir}/etc/ssh/sshd_config \
	-e "/^[# ]*PermitRootLogin .+$/d" \
	-e "/^[# ]*PermitEmptyPasswords .+$/d" \
	-e "/^[# ]*PubkeyAuthentication .+$/d"

	echo "
PermitRootLogin yes
PermitEmptyPasswords yes
PubkeyAuthentication yes
" | tee -a ${rootfsDir}/etc/ssh/sshd_config >/dev/null
}

parse_args() {
	[ -n "${1:-}" ] && case ${1:-} in
		-k)
			keepRoot=1
			shift
			;;

		-h)
			usage
			exit 0
			;;

		-*)
			echo "ERROR: unrecognized option \"$1\""
			usage
			exit 127
			;;
	esac

	flavor="${1:-}"
	if [ -z "${flavor:-}" ]; then
		flavor="alpine"
	fi
}

usage() {
	cat << EOF
USAGE:

	$(basename "$0") [options] [DISTRO-FLAVOR]

Create a initrd based on the specified distro flavor: alpine or suse.
If not specified, the alpine distro is used.

Options:

    -h             Show this help

    -k             Only Compress a previously created rootfs into an initrd image

EOF
}

main() {
	is_a_container || { echo "This needs to be run inside a container!"; exit 127; }
	parse_args $@

	case $flavor in
		alpine)
			setup_alpine
			;;

		suse)
			echo "SUSE flavor support is WIP"
			exit 127
			;;

		*)
			echo "not a valid flavor: $flavor"
			exit 127
			;;
	esac

	cd $buildDir
	# delete prev stuff
	rm -rf initrd.img

	if [ -z "$keepRoot" ]; then
		rm -rf "$rootfsDir"
		echo "INFO: building rootfs for flavor: $flavor"

		case $flavor in
			alpine)
				rootfs_alpine
				;;

			suse)
				rootfs_suse
				# stuff not needed in a micro VM
				rm -fr ${rootfsDir}/usr/share/{man,locale,licenses,kbd,misc,bash,bash-completion,terminfo,cracklib,zsh,help} ${rootfsDir}/usr/local/man
				chroot $rootfsDir /bin/sh -c 'echo -e "root\nroot" | passwd root'
				;;

			*)
				echo "not a valid flavor: $flavor"
				exit 127
				;;
		esac

		# set boot and account
		ln -sf /sbin/init ${rootfsDir}/init
		setup_ssh_key
		setup_ssh_insecure
	fi



	echo "INFO: compresing initrd"
	# create gz'ed cpio
	{ cd $rootfsDir; find . -print0 | cpio --null --create --verbose --format=newc | gzip --best > ${buildDir}/${initrdFile}; cd - >/dev/null; }

	cd - >/dev/null

	echo "INFO: done!"
}

main $@
exit 0
