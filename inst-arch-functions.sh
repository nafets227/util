#! /bin/bash
#
# inst-arch-functgion.sh
#
# Install helper functions for Arch Linux
#
# (C) 2014-2018 Stefan Schallenberg
#

##### Helper for arch-chroot #################################################
function inst-arch_chroot-helper() {
	# this helper function copies the stdin into a file and then executed
	# this file in the chroot.
	# This prevents the current shell from losing its tty and behaving as
	# ^Z has been pressed, i.e. prompting "[1] has been stopped" and user
	# would have to enter "fg" to resume the stopped job.
	local rc=0
		cat >"$1/inst-arch_chroot-helper-temp" &&
		chmod +x "$1/inst-arch_chroot-helper-temp" &&
		arch-chroot "$@" /inst-arch_chroot-helper-temp
	rc=$?
	rm "$1/inst-arch_chroot-helper-temp"
	return $rc
}

#### Setup Filesystems #######################################################
function inst-arch_init() {
	# Parameters:
	#    1 - hostname
	#    2 - rootdev
	#    3 - boot device [optional]
	#    4 - boot mount point [options, default /boot/efi]
	local name="$1"
	local rootdev="$2"
	local bootdev="$3"
	local bootmnt="${4-/boot/efi}"

	printf "About to install Arch Linux for %s\n" "$name" >&2
	inst-arch_destroy "$rootdev" "$bootdev" || return 1

	inst-arch_initinternal "$name" "$rootdev" "$bootdev" "$bootmnt" || return 1

	return 0
}

#### Setup Filesystems for virtual machines (make partitions) ################
function inst-arch_init-fulldisk () {
	# Parameters:
	#    1 - hostname
	#    2 - device
	#    3 - boot mount point [options, default /boot/efi]
	#    4 - size of file-backed disk. Ignored for device backed disk
	local name="$1"
	local diskdev="$2"
	local bootmnt="${3:-/boot/efi}"
	local disksize="${4:-10G}"

	# jscpd:ignore-start
	printf "About to install Arch Linux for %s\n" "$name" >&2
	inst-arch_destroy-disk "$diskdev" || return 1

	if [ ! -b "$diskdev" ] ; then
		printf "Creating Disk-Device %s (size=%s)\n" "$diskdev" "$disksize"
		if ! fallocate -l "$disksize" "$diskdev"
		then
			printf "Falling back to dd since fallocate is not working.\n" >&2
			dd if=/dev/zero "of=$diskdev" count=0 bs=1 "seek=$disksize" || return 1
		fi
	fi
	# jscpd:ignore-end

	# Create partitions and root Filesystems and mount it
	sfdisk "$diskdev" <<-EOF || return 1
		label: gpt
		1 : size=256M, type="EFI System", name="$name-efi"
		2 : type="Linux root (x86-64)", name="$name-root"
		EOF

	# jscpd:ignore-start
	parts=$(kpartx -asv "$(realpath "$diskdev")" | \
		sed -n -e 's:^add map \([A-Za-z0-9\-]*\).*:\1:p') &&
	part_efi=$(head -1 <<<"$parts") &&
	part_root=$(tail -1 <<<"$parts") \
	|| return 1

	INSTALL_DEV=$(losetup | grep "$diskdev" | cut -d" " -f 1) || return 1
	if [ -z "$INSTALL_DEV" ] ; then
		INSTALL_DEV="$diskdev"
	fi
	INSTALL_FINALIZE_CMD="kpartx -d $(realpath "$diskdev")"
	# jscpd:ignore-end

	inst-arch_initinternal "$name" "/dev/mapper/$part_root" \
		"/dev/mapper/$part_efi" "$bootmnt" \
		|| return 1

	return 0
}

#### Setup Filesystems for a directory, i.e. NFS-root ########################
function inst-arch_init-dir () {
	# Parameters:
	#    1 - hostname
	#    2 - rootdir
	local name="$1"
	local rootdir="$2"
	local bootmnt="${3-/boot}"

	if [ -e "$rootdir" ] ; then
		printf "Refusing to install Arch Linux for %s on existing dir %s\n" \
			"$name" "$rootdir" >&2
		return 1
	fi

	printf "About to install Arch Linux for %s on %s\n" "$name" "$rootdir" >&2

	# create tempdir to temporary mount the filesystems
	mkdir -p \
		"$rootdir/dev/pts" \
		"$rootdir/dev/shm" \
		"$rootdir/proc" \
		"$rootdir/run" \
		"$rootdir/sys" \
		"$rootdir/tmp" \
		"$rootdir/var/cache/pacman" \
		&&
	INSTALL_ROOT="$rootdir" &&
	INSTALL_BOOT="$bootmnt" &&
	mount --bind "$INSTALL_ROOT" "$INSTALL_ROOT" &&

	# mount filesystems needed for chroot
	# filesystem list is taken from arch-chroot
	mount proc "$INSTALL_ROOT/proc" -t proc -o nosuid,noexec,nodev &&
	mount sys "$INSTALL_ROOT/sys" -t sysfs -o nosuid,noexec,nodev,ro &&
	mount udev "$INSTALL_ROOT/dev" -t devtmpfs -o mode=0755,nosuid &&
	mount devpts "$INSTALL_ROOT/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec &&
	mount shm "$INSTALL_ROOT/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev &&
	mount run "$INSTALL_ROOT/run" -t tmpfs -o nosuid,nodev,mode=0755 &&
	mount tmp "$INSTALL_ROOT/tmp" -t tmpfs -o mode=1777,strictatime,nodev,nosuid &&

	# share package cache with installing host
	mount --bind /var/cache/pacman "$INSTALL_ROOT/var/cache/pacman" &&

	# Important: export INSTALL_ROOT now to let the caller do cleanup with
	# the funtion inst-arch_finalize
	export INSTALL_ROOT INSTALL_BOOT &&

	true || return 1

	return 0
}

#### Internal helper for setting up Filesystems in any environment ###########
#### (partition based or fulldisk) ###########################################
function inst-arch_initinternal () {
	local name="$1"
	local rootdev="$2"
	local bootdev="$3"
	local bootmnt="$4"

	#install needed utilities
	pacman -S --needed --noconfirm arch-install-scripts dosfstools >&2 &&

	# create tempdir to temporary mount the filesystems
	INSTALL_ROOT=$(mktemp --directory --tmpdir inst-arch.XXXXXXXXXX) &&
	true || return 1

	# Important: export INSTALL_ROOT now to let the caller do cleanup with
	# the funtion inst-arch_finalize
	export INSTALL_ROOT

	INSTALL_BOOT="$bootmnt" || return 1
	export INSTALL_BOOT || return 1

	# Create root Filesystems and mount it
	wipefs --all --force "$rootdev" || return 1
	mkfs.ext4 "$rootdev" >&2 || return 1
	mount "$rootdev" "$INSTALL_ROOT" >&2 || return 1

	# create boot filesystem and mount (if any)
	if [ -n "$bootdev" ]; then
		wipefs --all --force "$bootdev" || return 1
		mkfs.fat -F32 "$bootdev" >&2 || return 1
		mkdir -p "$INSTALL_ROOT$bootmnt" >&2 || return 1
		mount "$bootdev" "$INSTALL_ROOT$bootmnt" >&2 || return 1
	fi

	return 0
}

#### Tear down filesystems ###################################################
function inst-arch_finalize {
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -z "$INSTALL_BOOT" ] ; then
		printf "%s: Error \$INSTALL_BOOT is not set\n" \
			"${FUNCNAME[0]}" >&2
		return 1
	fi

	# / and /efi are automatically mounted by systemd, so we ignore them here.
	if [ "$INSTALL_BOOT" != "/efi" ] ; then
		genfstab -U -p -f "$INSTALL_ROOT$INSTALL_BOOT" "$INSTALL_ROOT" \
			>>"$INSTALL_ROOT/etc/fstab" || return 1
	fi

	# From here on we do not do any error handling.
	# We just do our best to cleanup things.

	umount --recursive --detach-loop "$INSTALL_ROOT"

	if [ -n "$INSTALL_FINALIZE_CMD" ] ; then
		$INSTALL_FINALIZE_CMD
	fi

	unset INSTALL_ROOT INSTALL_BOOT

	return 0
}

##### Wipe filesystems #######################################################
function inst-arch_destroy() {
	# Parameters:
	#    1 - rootdev
	#    2 - boot device [optional]
	local rootdev="$1"
	local bootdev="$2"

	printf "About to destroy Arch Linux data.\n\tRoot-Device: %s (%s)\n" \
		"$rootdev" "$(realpath "$rootdev")" >&2
	if [ -n "$bootdev" ]; then
		printf "\t Boot-Device: %s (%s)\n" \
			"$bootdev" "$(realpath "$bootdev")" >&2
		printf "\tWarning: All data will be DELETED!\n" >&2
	fi
	[ -t 0 ] && read -r -p "Press Enter to Continue, use Ctrl-C to break."

	wipefs --all --force "$rootdev" || return 1
	if [ -n "$bootdev" ]; then
		wipefs --all --force "$bootdev" || return 1
	fi

	return 0
}

#### Wipe disk and remove file backend #######################################
function inst-arch_destroy-disk () {
	# Parameters:
	#    1 - device
	local diskdev="$1"

	printf "About to destroy Arch Linux data.\n\tDisk Device %s (%s)\n" \
		"$diskdev" "$(realpath "$diskdev")" >&2
	printf "\tWarning: All data will be DELETED!\n" >&2
	[ -t 0 ] && read -r -p "Press Enter to Continue, use Ctrl-C to break."

	if [ -b "$diskdev" ] ; then
		wipefs --all --force "$diskdev" || return 1
	elif [ -e "$diskdev" ] ; then
		rm "$diskdev" || return 1
	fi

	return 0
}

#### Install auto-update timer ###############################################
function inst-archinternal_updatetimer {
	local updatetim="$1"

	# Configure an autoupdate Service and timer.
	# if updatetim is blank, disable it
	printf "Configuring nafetsde-autoupdate at %s on %s\n" \
		"$updatetim" "$INSTALL_ROOT" >&2

	install -o 0 -g 0 -m 700 \
		"$(dirname "${BASH_SOURCE[0]}")/inst-arch/autoupdate.sh" \
		"$INSTALL_ROOT/usr/local/sbin/autoupdate.sh" \
		&&

	install-timer \
		"nafetsde-autoupdate" \
		"/usr/local/sbin/autoupdate.sh $INSTALL_BOOT" \
		"" \
		"" \
		"*-*-* ${updatetim-1:00}" \
	|| return 1

	if [ -z "$updatetim" ] ; then
		systemctl --root "$INSTALL_ROOT" \
			disable nafetsde-autoupdate.timer \
		|| return 1
	fi

	return 0
}

##### configure an architecture to install ###################################
function inst-arch_confarchinternal {
	local arch_cur

	arch_cur=$(uname -m) &&
	INSTALL_ARCH=${1:-$arch_cur} &&
	true || return 1

	INSTALL_EARLY_PKG=( pacman pacman-mirrorlist mkinitcpio )

	if [ "$INSTALL_ARCH" == "x86_64" ] ; then
		INSTALL_REPOURL="https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"
		INSTALL_KEYRING_PKG=( archlinux-keyring )
	elif [ "$INSTALL_ARCH" == "aarch64" ] ; then
		INSTALL_REPOURL="http://mirror.archlinuxarm.org/\$arch/\$repo"
		INSTALL_KEYRING_PKG=( archlinux-keyring archlinuxarm-keyring )
	else
		printf "%s: unsupported Architecture %s\n" \
			"${FUNCNAME[0]}" "$INSTALL_ARCH" >&2
		return 1
	fi

	return 0
}

##### initialise keyring on mounted system ###################################
function inst-arch_keyringinternal {
	local keyringdir
	# Setup a Keyring for new system
	keyringdir=/usr/share/pacman/keyrings/$(basename "$INSTALL_ROOT") &&
	ln -s \
		"$INSTALL_ROOT/usr/share/pacman/keyrings" \
		"$keyringdir" &&
	sed -e "s:Include = /:Include = $INSTALL_ROOT/:" \
			-e "s:#DBPath.*:DBPath = $INSTALL_ROOT/var/lib/pacman/:" \
			-e "s:#LogFile.*:LogFile = $INSTALL_ROOT/var/log/pacman.log:" \
			-e "s:#GPGDir.*:GPGDir = $INSTALL_ROOT/etc/pacman.d/gnupg/:" \
			-e "s:#HookDir.*:HookDir = $INSTALL_ROOT/etc/pacman.d/hooks/:" \
		<"$INSTALL_ROOT/etc/pacman.conf" \
		>"$INSTALL_ROOT/etc/pacman.conf.installroot" &&
	pacman-key \
		--config "$INSTALL_ROOT/etc/pacman.conf.installroot" \
		--init \
		&&
	# workaround, probably solved when both archlinux x86_64 and aarch64 update
	# to gnupg 2.4.x
	echo allow-weak-key-signatures >>"$INSTALL_ROOT/etc/pacman.d/gnupg/gpg.conf" &&
	local keyrings=( ) &&
	for f in "$keyringdir"/*.gpg ; do
		keyrings+=( "$(basename "$INSTALL_ROOT")/$(basename "$f" .gpg)" )
	done
	pacman-key \
		--config "$INSTALL_ROOT/etc/pacman.conf.installroot" \
		--populate "${keyrings[@]}" \
		&&
	rm "$keyringdir" &&
	killall "gpg-agent" -u root &&
	true || return 1

	return 0
}

##### Install Arch Linux on a new filesystem #################################
function inst-arch_baseos {
	# Parameters:
	#    1 - hostname
	#    2 - additional package [optional]
	#    3 - additional Modules in initrd [optional]
	#    4 - time to run autoupdate [default=blank means disabled]
	#    5 - kernal parmeters [default=blank]
	#    6 - architecture [default=current arch we are running on]
	#    7 - additional pacman repositories to pull
	#        Format: reponame, url [ ,SigLevel ]
	local name="$1"
	local extrapkg="$2"
	local extramod="$3"
	local updatetim="$4"
	local kernel_parm="$5"
	local arch="$6"
	local repos="$7"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	inst-arch_confarchinternal "$arch" || return 1

	printf "Installing Arch Linux on %s for %s (%s). \n\tExtra Packages: %s\n\tExtra Modules: %s\n" \
		"$INSTALL_ROOT" "$name" "$arch" "$extrapkg" "$extramod" >&2

	# set Hostname, locale and root password. Do it befor installing the
	# system because packages will already update passwd and shadow
	# for german use: --locale=LANG=de_DE.UTF-8
	mkdir "$INSTALL_ROOT/etc" &&
	systemd-firstboot --root="$INSTALL_ROOT" \
		--hostname="$name" \
		--locale="en_DK.UTF-8" \
		--locale-messages="en_US.UTF-8" \
		--keymap="de-latin1-nodeadkeys" \
		--timezone="Europe/Berlin" \
		--copy-root-password \
		--copy-root-shell \
		--setup-machine-id \
		&&

	# pacstrap options:
	# -C <config>    Use an alternate config file for pacman
	# -c Use the package cache on the host, rather than the target
	# -D Skip pacman dependency checks
	# -G Avoid copying the host's pacman keyring to the target
	# -i Prompt for package confirmation when needed (run interactively)
	# -K Initialize an empty pacman keyring in the target (implies '-G')
	# -M Avoid copying the host's mirrorlist to the target
	# -N Run in unshare mode as a regular user
	# -P Copy the host's pacman config to the target
	# -U Use pacman -U to install packages
	pacstrap -C <( cat <<-EOF
			[options]
			Architecture = $INSTALL_ARCH
			SigLevel=Never
			[core]
			Server = $INSTALL_REPOURL
			[extra]
			Server = $INSTALL_REPOURL
			EOF
			) \
		-c -D -G -M \
		"$INSTALL_ROOT" \
		"${INSTALL_EARLY_PKG[@]}" "${INSTALL_KEYRING_PKG[@]}" &&

	# ensure at least on server is available in mirrorlist
	# current x86_64 mirrorlist has all servers commented out.
	cat >>"$INSTALL_ROOT/etc/pacman.d/mirrorlist" <<-EOF &&

		# added by ${BASH_FUNC[0]} at $(date)
		Server = $INSTALL_REPOURL
		EOF

	if [ -n "$repos" ] ; then
		local reponame repourl reposig
		IFS="," read -r reponame repourl reposig <<<"$repos"

		inst-arch_add_repo "$reponame" "$repourl" "$reposig" || return 1
	fi

	#Bootstrap the new system
	inst-arch_keyringinternal &&
	true || return 1

	# Now include the needed modules in initcpio
	if [ -n "$extramod" ] ; then
		util_updateConfig "$INSTALL_ROOT/etc/mkinitcpio.conf" \
			"MODULES" "( $extramod )" \
		|| return 1
	fi

	#shellcheck disable=SC2086 # extrapkg contains multiple parms
	pacstrap -C "$INSTALL_ROOT/etc/pacman.conf.installroot" \
		-c -G -M \
		"$INSTALL_ROOT" \
		base openssh grub linux-firmware pacutils pacman-contrib less \
		"${INSTALL_EARLY_PKG[@]}" "${INSTALL_KEYRING_PKG[@]}" \
		$extrapkg &&
	true || return 1

	# Workaround a bug in Archlinux that /dev cannot be unmounted at the end of pacstrap without raising an error
	umount "$INSTALL_ROOT/dev" # do not check the RC here!

	cat >>"$INSTALL_ROOT/etc/locale.gen" <<-EOF &&

		# by ${BASH_FUNC[0]}
		de_DE.UTF-8 UTF-8
		en_DK.UTF-8 UTF-8
		en_US.UTF-8 UTF-8
		EOF

	arch-chroot "$INSTALL_ROOT" locale-gen &&

	# We insert parameters for console to be able to use it when starting as
	# virtual machine. But it does not work when starting bare-metal:
	# kernel_parm+=" consoleblank=0 console=ttyS0,115200n8 console=tty0"
	cat >"$INSTALL_ROOT/etc/kernel/cmdline" <<-EOF &&
		${kernel_parm}
		EOF

	inst-archinternal_updatetimer "$updatetim" &&
	systemctl --root="$INSTALL_ROOT" enable sshd.service &&
	true || return 1

	return 0
}

##### create Grub Config #####################################################
function inst-arch_bootmgr-grubconfig {
	# Configure Grub for EFI or raw boot ( in /boot/grub/grub.cfg )
	printf "Configuring Grub on %s\n" "$INSTALL_ROOT" >&2

	# Install grub2 Config for booting efi or raw.
	mkdir -p "$INSTALL_ROOT/boot/grub" 2>/dev/null &&

	util_updateConfig "$INSTALL_ROOT/etc/default/grub" \
		"GRUB_CMDLINE_LINUX" \
		"\"\$(cat /etc/kernel/cmdline)\"" &&

	inst-arch_chroot-helper "$INSTALL_ROOT" <<-"EOFGRUB" &&
		grub-mkconfig >/boot/grub/grub.cfg || exit 1
		EOFGRUB

	true || return 1

	return 0
}

##### Install Grub for efi ###################################################
function inst-arch_bootmgr-grubefi {
	# Parameters:
	#    1 - EFI Workaround (default: 1)
	local efibugfix="${1:-1}"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -z "$INSTALL_BOOT" ] ; then
		printf "%s: Error \$INSTALL_BOOT is not set\n" \
			"${FUNCNAME[0]}" >&2
		return 1
	fi

	inst-arch_bootmgr-grubconfig || return 1

	printf "Installing Grub-EFI on %s in %s\n" "$INSTALL_ROOT" "$INSTALL_BOOT" >&2

	inst-arch_chroot-helper "$INSTALL_ROOT" <<-EOFGRUB || return 1
		pacman -S --needed --noconfirm efibootmgr || exit 1
		grub-install \
			--target=x86_64-efi \
			--efi-directory=$INSTALL_BOOT \
			--no-bootsector \
			--no-nvram \
			|| exit 1
		EOFGRUB

	if [ "$efibugfix" == "1" ] ; then
		# Bugfix EFI buggy BIOS - will be redone by systemd ervice
		# nafetsde-efiboot on each shutdown
		mkdir -p "$INSTALL_ROOT/$INSTALL_BOOT/EFI/BOOT" 2>/dev/null
		cp -a	"$INSTALL_ROOT/$INSTALL_BOOT/EFI/arch/grubx64.efi" \
			"$INSTALL_ROOT/$INSTALL_BOOT/EFI/BOOT/BOOTx64.EFI" \
			|| return 1

		cat >"$INSTALL_ROOT/etc/systemd/system/nafetsde-efiboot.service" <<-EOF || return 1
			# nafetsde-efiboot.service
			#
			# (C) 2015 Stefan Schallenberg
			#
			[Unit]
			Description="efiboot Updates on Shutdown for Buggy EFI-BIOS"

			[Service]
			Type=oneshot
			RemainAfterExit=yes
			ExecStop=/usr/bin/cp -a $INSTALL_BOOT/EFI/arch/grubx64.efi $INSTALL_BOOT/EFI/BOOT/BOOTx64.EFI

			[Install]
			WantedBy=multi-user.target
			EOF
		systemctl --root="$INSTALL_ROOT" enable nafetsde-efiboot.service
	else
		cat >"$INSTALL_ROOT/$INSTALL_BOOT/startup.nsh" <<-EOF || return 1
			EFI\arch\grubx64.efi
			EOF
	fi

	return 0
}

##### Install Grub for raw ###################################################
function inst-arch_bootmgr-grubraw {
	# Parameters:
	#    1 - rawdev [optional, autoprobed to device of INSTALL_ROOT]
	#    2 - bootdir [optional, default /boot]
	local rawdev="$1"
	local bootdir="${2-/boot}"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	if [ -z "$rawdev" ] && [ -n "$INSTALL_DEV" ] ; then
		rawdev="$INSTALL_DEV"
		printf "Autoproved Raw Device to INSTALL_DEV=%s\n" "$rawdev" >&2
	elif [ -z "$rawdev" ] ; then
		rawdev=$(grep "$INSTALL_ROOT " </proc/mounts \
			| cut -d" " -f 1)
		printf "Autoprobed Raw Device to %s\n" "$rawdev" >&2
	fi

	if [ ! -b "$rawdev" ] ; then
		printf "Raw Device %s is no block device.\n" "$rawdev" >&2
		return 1
	fi

	inst-arch_bootmgr-grubconfig || return 1

	printf "Installing Grub-Raw on %s (%s) for %s\n" \
		"$INSTALL_ROOT" "$rawdev" "$bootdir" >&2

	inst-arch_chroot-helper "$INSTALL_ROOT" <<-EOF || return 1
		grub-install \\
			--target=i386-pc \\
			--boot-directory=$bootdir \\
			--force \\
			$rawdev \\
			|| exit 1
	EOF

	return 0
}

#### inst-arch_bootmgr-systemd ###############################################
function inst-arch_bootmgr-systemd {

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -z "$INSTALL_BOOT" ] ; then
		printf "%s: Error \$INSTALL_BOOT is not set\n" \
			"${FUNCNAME[0]}" >&2
		return 1
	elif [ ! -w "$INSTALL_ROOT/etc/mkinitcpio.d/linux.preset" ] ; then
		printf "%s: Error %s  does not exist or ist not writable\n" \
			"${FUNCNAME[0]}"  "/etc/mkinitcpio.d/linux.preset" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	cat >>"$INSTALL_ROOT/etc/mkinitcpio.d/linux.preset" <<-EOF &&
		default_efi_image="$INSTALL_BOOT/EFI/Linux/archlinux-linux.efi"
		default_options="-A systemd"
		fallback_efi_image="$INSTALL_BOOT/EFI/Linux/archlinux-linux-fallback.efi"
		fallback_options="-S autodetect -A systemd"

		ALL_microcode=(/boot/*-ucode.img)
		EOF

	touch "$INSTALL_ROOT/etc/kernel/cmdline" &&
	arch-chroot "$INSTALL_ROOT" bootctl install --no-variables &&
	arch-chroot "$INSTALL_ROOT" mkinitcpio -p linux &&
	systemctl --root="$INSTALL_ROOT" enable systemd-boot-update.service &&
	true || return 1

	return 0
}

#### inst-arch_add_repo ######################################################
function inst-arch_add_repo () {
	local -r PACCONF=$INSTALL_ROOT/etc/pacman.conf
	repo="$1"
	srv="${2:-"MIRROR"}"
	sig="$3"

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -w "$PACCONF" ] ; then
		printf "%s: Error /etc/pacman.conf does not exist or ist not writable\n" \
			"${FUNCNAME[0]}"  >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	printf "[%s]\n" "$repo" >>"$PACCONF"
	if [ -n "$sig" ] ; then
		printf "SigLevel = %s\n" "$sig" >>"$PACCONF" || return 1
	fi

	for f in $srv ; do
		if [ "$f" == "MIRROR" ] ; then
			printf "Include = /etc/pacman.d/mirrorlist\n" \
				>>"$PACCONF" || return 1
		else
			printf "Server = %s\n" "$f" >>"$PACCONF" || return 1
		fi
	done

	#----- Closing -------------------------------------------------------
	printf "Added ArchLinux Repo %s" "$repo" >&2
	[ -z "$sig" ] || printf " (SigLevel %s)" "$sig" >&2
	[ -z "$srv" ] || printf " (Srv %s)" "$srv" >&2
	printf "\n"

	return 0
}

#### inst-arch_getpkgurl #####################################################
function inst-arch_getpkgurl {
	local -r pkg="$1"

	if  [ -z "$pkg" ] ; then
		printf "%s: Error no parm given\n" "${BASH_FUNC[0]}"
		return 1
	fi

	local -r PKGURL="https://archive.archlinux.org/packages/.all"
	local -r PKGURL2="https://alaa.ad24.cz/packages/.all"
	local arch

	arch=$(arch-chroot "$INSTALL_ROOT" /usr/bin/pacconf |
		sed -n 's/Architecture[[:blank:]]*=[[:blank:]]*//p') || return 1
	if [ -z "$arch" ] ; then
		printf "%s: Did not find Architecture = in pacman conf\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	for url in \
		{$PKGURL,$PKGURL2}/$pkg-{$arch,any}.pkg.tar.{zst,xz} ;
	do
		if curl \
			--head \
			-o /dev/null \
			--silent \
			--fail "$url" \
			--location \
			-w "%{url} %{http_code}\n" \
			>/dev/stderr ;
		then
			printf "%s\n" "$url"
			return 0
		fi
	done

	printf "Error: package %s not found.\n\t URLs: %s\n" \
		"$pkg" "{$PKGURL,$PKGURL2}/$pkg-{$arch,any}.pkg.tar.{zst,xz}"

	return 1
}

#### inst-arch_fixverpkg #####################################################
function inst-arch_fixverpkg () {
	local -r PACCONF=$INSTALL_ROOT/etc/pacman.conf

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -w "$PACCONF" ] ; then
		printf "%s: Error /etc/pacman.conf does not exist or ist not writable\n" \
			"${FUNCNAME[0]}"  >&2
		return 1
	elif ! grep "IgnorePkg" "$PACCONF" ; then
		printf "%s: Error /etc/pacman.conf does not contain IgnorePkg\n" \
			"${FUNCNAME[0]}"  >&2
		return 1
	elif [ ! -x "$INSTALL_ROOT/usr/bin/pacconf" ] ; then
		printf "%s: Error /usr/bin/pacconf does not exist or ist not executable\n" \
			"${FUNCNAME[0]}"  >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	local pkgurl pkgname
	local pkgurls=( )
	local pkgnames=( )
	for pkg in "$@" ; do
		pkgurl=$(inst-arch_getpkgurl "$pkg") &&
		pkgname=${pkg%-*-*} &&
		pkgurls+=( "$pkgurl" ) &&
		pkgnames+=( "$pkgname" ) &&
		true || return 1
	done

	arch-chroot "$INSTALL_ROOT" \
		pacman -U --needed --noconfirm "${pkgurls[@]}" &&

	pkgnames_old=$(util_getConfig "$PACCONF" "IgnorePkg") &&
	util_updateConfig "$PACCONF" \
		"IgnorePkg" "$pkgnames_old ${pkgnames[*]}" &&
	true || return 1

	#----- Closing -------------------------------------------------------
	printf "Added Package(s) with fixed version %s\n" "$@" >&2

	return 0
}

##### main ####################################################################

# do nothing
