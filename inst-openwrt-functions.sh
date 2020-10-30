#!/usr/bin/env bash
#
# Install function for OpenWRT as VM in libvirt
#
# (C) 2019 Stefan Schallenberg
#

##### Install OpenWRT and leave it mounted ###################################
function inst-openwrt_init {
	# Parameters:
	#    1 - device
	#    2 - openwrt version
	local diskdev="$1"
	local openwrt_version="$2"
	local openwrt_url
	openwrt_url="https://downloads.openwrt.org/releases/$openwrt_version"
	openwrt_url+="/targets/x86/generic"
	openwrt_url+="/openwrt-$openwrt_version-x86-generic-combined-ext4.img.gz"

	printf "About to install OpenWRT Version %s\n" "$openwrt_version" >&2
	printf "Disk-Device is %s (%s)\n" \
			"$diskdev" "$(realpath $diskdev)" >&2
	printf "Warning: All data on %s will be DELETED!\n" \
			"$diskdev" >&2
	read -p "Press Enter to Continue, use Ctrl-C to break."

	openwrt_imggz=$(util_download "$openwrt_url") || return 1

	# Create partitions and root Filesystems and mount it
	if [ -e "$diskdev" ] ; then
		wipefs --all --force $diskdev || return 1
	fi
	gunzip -c $openwrt_imggz >$diskdev || return 1

	parts=$(kpartx -asv "$(realpath "$diskdev")" | \
		sed -n -e 's:^add map \([A-Za-z0-9\-]*\).*:\1:p') &&
	part_boot=$(head -1 <<<$parts) &&
	part_root=$(tail -1 <<<$parts) \
	|| return 1

	INSTALL_FINALIZE_CMD="kpartx -d $(realpath "$diskdev")"

	# create tempdir to temporary mount the filesystems
	INSTALL_ROOT=$(mktemp --directory --tmpdir inst-arch.XXXXXXXXXX) || return 1

	# Important: export INSTALL_ROOT now to let the caller do cleanup with
	# the funtion inst-arch_finalize
	export INSTALL_ROOT

	mount /dev/mapper/$part_root $INSTALL_ROOT >&2 || return 1
	# not needed:
	# mount /dev/mapper/$part_boot $INSTALL_ROOT/boot >&2 || return 1

	return 0
}

#### chroot into system, enabling network ####################################
function inst-openwrt_chroot {
	if		[ -z "$INSTALL_ROOT" ] ||
			[ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	touch $INSTALL_ROOT/tmp/resolv.conf &&
	mount --bind -o ro \
		$(realpath /etc/resolv.conf) \
		$INSTALL_ROOT/tmp/resolv.conf &&
	chroot $INSTALL_ROOT /bin/ash -s -c \
		'export PATH="/usr/sbin:/usr/bin:/sbin:/bin"' &&
	umount $INSTALL_ROOT/tmp/resolv.conf &&
	rm $INSTALL_ROOT/tmp/resolv.conf \
	|| return 1

	return 0
}

#### Tear down filesystems ###################################################
function inst-openwrt_finalize {
	if [ -z "$INSTALL_ROOT" ] ; then
		return 0
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	# From here on we do not do any error handling.
	# We just do our best to cleanup things.

	# if [ "$1" != "--no-passwd-expire" ] ; then
	#		# arch-chroot will fail on non-x86 systems. passwd --root also fails,
	#		# so we kindly ignore if it fails.
	#	arch-chroot $INSTALL_ROOT <<-EOF
	#		passwd -e root
	#		EOF
	# else
	#	printf "Skipping expire root password\n"
	# fi

	umount --recursive --detach-loop "$INSTALL_ROOT"

	if [ ! -z "$INSTALL_FINALIZE_CMD" ] ; then
		$INSTALL_FINALIZE_CMD
	fi

	unset INSTALL_ROOT

	return 0
}

