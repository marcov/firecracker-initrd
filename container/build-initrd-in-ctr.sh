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
compress=
addNetwork=1
fcnetPath="/usr/local/bin/fcnet-setup.sh"
initrdFile="initrd.img"

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
	kiwi system prepare --description=/container --allow-existing-root --root "$rootfsDir"

	rm -f ${rootfsDir}/etc/systemd/system/getty.target.wants/getty@tty1.service
	ln -sf /usr/lib/systemd/system/getty@.service ${rootfsDir}/etc/systemd/system/getty.target.wants/getty@ttyS0.service
}

setup_alpine() {
	apk add openssh gzip gcc libc-dev
}

rootfs_alpine() {
	pkgs="alpine-base \
			openrc \
			util-linux"

	mkdir "${rootfsDir}"

	[ -n "$addNetwork" ] && pkgs=" \
							$pkgs    \
							iptables \
							iproute2 \
							openssh \
							grep"

	apk -X "http://dl-5.alpinelinux.org/alpine/latest-stable/main" -U --allow-untrusted --root ${rootfsDir} --initdb \
		add $pkgs

	cd ${rootfsDir}

	# Configure startup
	ln -sf /etc/init.d/devfs  ./etc/runlevels/boot/devfs
	ln -sf /etc/init.d/procfs ./etc/runlevels/boot/procfs
	ln -sf /etc/init.d/sysfs  ./etc/runlevels/boot/sysfs

	ln -sf agetty                   ./etc/init.d/agetty.ttyS0
	echo "ttyS0" >> ./etc/securetty
	ln -sf /etc/init.d/agetty.ttyS0 ./etc/runlevels/default/agetty.ttyS0

	if [ -n "$addNetwork" ]; then
		ln -sf networking             ./etc/init.d/net.eth0
		ln -sf /etc/init.d/networking ./etc/runlevels/default/networking
		ln -sf /etc/init.d/net.eth0   ./etc/runlevels/default/net.eth0

		ln -sf sshd                  ./etc/init.d/sshd.eth0
		ln -sf /etc/init.d/sshd.eth0 ./etc/runlevels/default/sshd.eth0

		# Configure networking
		cat >> ./etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
EOF

		## fcnet configures eth0 IP address based on the MAC address provided
		cp /guest/$(basename ${fcnetPath}) ./${fcnetPath}
		chown root ./${fcnetPath}
		chmod 755 ./${fcnetPath}
		cat >> ./etc/init.d/fcnet << EOF
#!/sbin/openrc-run

command="${fcnetPath}"
EOF

		ln -sf /etc/init.d/fcnet ./etc/runlevels/default/fcnet
		chmod 755 ./etc/init.d/fcnet

		# Use a custom for boot done signaling to Firecracker
		local openrcInit="/sbin/openrc-init"
		mv ./sbin/init .${openrcInit}
		gcc -DOPENRC_INIT="\"${openrcInit}"\" -static -O3 -o ./sbin/init /guest/boot_done.c

		# Add apk repositories
		cp /etc/apk/repositories ./etc/apk/repositories

		chroot $rootfsDir /bin/sh -c 'echo -e "root\nroot" | passwd root'

	fi # [ -n "$addNetwork" ]

	cd - >/dev/null
}

setup_ssh_key() {
	rm -rf ssh-key
	mkdir -p ssh-key

	# Generate key for ssh access from host
	ssh-keygen -f ssh-key/id_rsa -N ""
	mkdir -m 0600 -p ${rootfsDir}/root/.ssh/
	cp ssh-key/id_rsa.pub ${rootfsDir}/root/.ssh/authorized_keys

	# Generate SSH keys for guest
	ssh-keygen -A -f ${rootfsDir} -N ""

	#Start ssh only when eth0 is set up
	cat >> ${rootfsDir}/etc/conf.d/sshd << EOF
sshd_disable_keygen="yes"
rc_need="net.eth0 fcnet"
EOF
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

	while [ "$#" -ge 1 ]; do
		case ${1:-} in
			-k)
				keepRoot=1
				shift
				;;

			-z)
				compress=1
				shift
				;;

			-h|--help)
				usage
				exit 0
				;;

			--minimal)
				addNetwork=
				shift
				;;

			-*)
				echo "ERROR: unrecognized option \"$1\""
				usage
				exit 127
				;;
		esac
	done

	flavor="${1:-}"
	if [ -z "${flavor:-}" ]; then
		flavor="alpine"
	fi
}

usage() {
	cat << EOF
USAGE:

	$(basename "$0") [options] [DISTRO-FLAVOR]

Creates an Alpine based initrd.

Options:

    -h             Show this help
    -k             Create an inirtd image from an existing rootfs at .${rootfsDir}
    -z             Compress the initrd using gzip
    --minimal      Create a minimal image without networking

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
		if [ -n "$addNetwork" ]; then
			setup_ssh_key
			setup_ssh_insecure
		fi
	fi



	echo "INFO: Creating initrd"
	# create (gz'ed) cpio

	if [ -n "$compress" ]; then
		compressor="gzip --best"
	else
		compressor="tee"
	fi

	{ cd $rootfsDir; find . -print0 | cpio --null --create --verbose --format=newc | ${compressor} > ${buildDir}/${initrdFile}; cd - >/dev/null; }

	cd - >/dev/null

	echo "INFO: done!"
}

main $@
exit 0
