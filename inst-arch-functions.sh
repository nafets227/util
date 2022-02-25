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
		cat >$1/inst-arch_chroot-helper-temp &&
		chmod +x $1/inst-arch_chroot-helper-temp &&
		arch-chroot "$@" /inst-arch_chroot-helper-temp
	rc=$?
	rm $1/inst-arch_chroot-helper-temp
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
	if [ -z "$bootdev" ]; then
		printf "Root-Device: %s (%s)\n" \
			"$rootdev" "$(realpath $rootdev)" >&2
		printf "Warning: All data on %s will be DELETED!\n" \
			"$rootdev" >&2
	else
		printf "Root-Device: %s (%s), Boot-Device: %s (%s) on %s\n" \
			"$rootdev" "$(realpath $rootdev)" \
			"$bootdev" "$(realpath $bootdev)" "$bootmnt" >&2
		printf "Warning: All data on %s and %s will be DELETED!\n" \
			"$rootdev" "$bootdev" >&2
	fi
	read -p "Press Enter to Continue, use Ctrl-C to break."

	inst-arch_initinternal "$name" "$rootdev" "$bootdev" "$bootmnt" || return 1

	return 0
}

#### Setup Filesystems for virtual machines (make partitions) ################
function inst-arch_init-fulldisk () {
	# Parameters:
	#    1 - hostname
	#    2 - device
	#    3 - boot mount point [options, default /boot/efi]
	local name="$1"
	local diskdev="$2"
	local bootmnt="${3-/boot/efi}"

	printf "About to install Arch Linux for %s\n" "$name" >&2
	printf "Disk-Device: %s (%s)\n" \
			"$diskdev" "$(realpath $diskdev)" >&2
	printf "Warning: All data on %s will be DELETED!\n" \
			"$diskdev" >&2
	read -p "Press Enter to Continue, use Ctrl-C to break."

	# Create partitions and root Filesystems and mount it
	if [ ! -e "$diskdev" ] ; then
		printf "Creating Disk-Devide %s (size=10G)\n" "$diskdev"
		fallocate -l 10G $diskdev
		if [ $? -ne 0 ] ; then
			printf "Falling back to dd since fallocate is not working.\n" >&2
			dd if=/dev/zero of=$diskdev count=0 bs=1 seek=10G || return 1
		fi
	else
		wipefs --all --force $diskdev || return 1
	fi

	sfdisk $diskdev <<-EOF || return 1
		label: gpt
		1 : size=256M, type="EFI System", name="$name-efi"
		2 : type="Linux root (x86-64)", name="$name-root"
		EOF

	parts=$(kpartx -asv "$(realpath "$diskdev")" | \
		sed -n -e 's:^add map \([A-Za-z0-9\-]*\).*:\1:p') &&
	part_efi=$(head -1 <<<$parts) &&
	part_root=$(tail -1 <<<$parts) \
	|| return 1

	INSTALL_DEV=$(losetup | grep $diskdev | cut -d" " -f 1) || return 1
	if [ -z "$INSTALL_DEV" ] ; then
		INSTALL_DEV="$diskdev"
	fi
	INSTALL_FINALIZE_CMD="kpartx -d $(realpath "$diskdev")"

	inst-arch_initinternal "$name" "/dev/mapper/$part_root" \
		"/dev/mapper/$part_efi" "$bootmnt" \
		|| return 1

	return 0
}

#### Setup Filesystems for virtual machines (make partitions) ################
function inst-arch_init-pidisk () {
	# Parameters:
	#    1 - hostname
	#    2 - device
	local name="$1"
	local diskdev="$2"

	printf "About to install Arch Linux for %s\n" "$name" >&2
	printf "Disk-Device: %s (%s)\n" \
			"$diskdev" "$(realpath $diskdev)" >&2
	printf "Warning: All data on %s will be DELETED!\n" \
			"$diskdev" >&2
	read -p "Press Enter to Continue, use Ctrl-C to break."

	# Create partitions and root Filesystems and mount it
	if [ ! -e "$diskdev" ] ; then
		printf "Creating Disk-Devide %s (size=8G) using dd\n" "$diskdev"
		dd if=/dev/zero of=$diskdev count=0 bs=1 seek=8G || return 1
	else
		wipefs --all --force $diskdev || return 1
	fi

	parted -s -- "$diskdev" mklabel msdos &&
	parted -s -- "$diskdev" mkpart primary fat32 128M 256M &&
	parted -s -- "$diskdev" mkpart primary ext4 256M 100% \
	|| return 1

	parts=$(kpartx -asv "$(realpath "$diskdev")" | \
		sed -n -e 's:^add map \([A-Za-z0-9\-]*\).*:\1:p') &&
	part_boot=$(head -1 <<<$parts | tail -1) &&
	part_root=$(tail -1 <<<$parts) \
	|| return 1

	INSTALL_DEV=$(losetup | grep $diskdev | cut -d" " -f 1) || return 1
	if [ -z "$INSTALL_DEV" ] ; then
		INSTALL_DEV="$diskdev"
	fi
	INSTALL_FINALIZE_CMD="kpartx -d $(realpath "$diskdev")"

	inst-arch_initinternal "$name" "/dev/mapper/$part_root" \
		"/dev/mapper/$part_boot" "/boot" \
		|| return 1

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
	pacman -S --needed --noconfirm arch-install-scripts dosfstools >&2

	# create tempdir to temporary mount the filesystems
	INSTALL_ROOT=$(mktemp --directory --tmpdir inst-arch.XXXXXXXXXX)
	[ $? -ne 0 ] && return 1

	# Important: export INSTALL_ROOT now to let the caller do cleanup with
	# the funtion inst-arch_finalize
	export INSTALL_ROOT

	INSTALL_BOOT="$bootmnt" || return 1
	export INSTALL_BOOT || return 1

	# Create root Filesystems and mount it
	wipefs --all --force $rootdev || return 1
	mkfs.ext4 $rootdev >&2 || return 1
	mount $rootdev $INSTALL_ROOT >&2 || return 1

	# create boot filesystem and mount (if any)
	if [ ! -z "$bootdev" ]; then
		mkfs.fat -F32 "$bootdev" >&2 || return 1
		mkdir -p $INSTALL_ROOT$bootmnt >&2 || return 1
		mount $bootdev $INSTALL_ROOT$bootmnt >&2 || return 1
	fi

	return 0
}

#### Tear down filesystems ###################################################
function inst-arch_finalize {
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	# From here on we do not do any error handling.
	# We just do our best to cleanup things.

	umount --recursive --detach-loop "$INSTALL_ROOT"

	if [ ! -z "$INSTALL_FINALIZE_CMD" ] ; then
		$INSTALL_FINALIZE_CMD
	fi

	unset INSTALL_ROOT INSTALL_BOOT

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
	local name="$1"
	local extrapkg="$2"
	local extramod="$3"
	local updatetim="$4"
	local kernel_parm="$5"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	printf "Installing Arch Linux on %s for %s. \n\tExtra Packages: %s\n\tExtra Modules: %s\n" \
		"$INSTALL_ROOT" "$name" "$extrapkg" "$extramod" >&2

	# set Hostname, locale and root password. Do it befor installing the
	# system because packages will already update passwd and shadow
	# for german use: --locale=LANG=de_DE.UTF-8
	mkdir $INSTALL_ROOT/etc
	systemd-firstboot --root=$INSTALL_ROOT \
		--hostname="$name" \
		--locale="en_DK.UTF-8" \
		--locale-messages="en_US.UTF-8" \
		--keymap="de-latin1-nodeadkeys" \
		--timezone="Europe/Berlin" \
		--copy-root-password \
		--copy-root-shell \
		--setup-machine-id \
	|| return 1

	#Bootstrap the new system
	pacstrap -c -d $INSTALL_ROOT base openssh grub linux linux-firmware pacutils $extrapkg || return 1
	genfstab -U -p $INSTALL_ROOT >$INSTALL_ROOT/etc/fstab || return 1

	# Now include the needed modules in initcpio
	if [ ! -z "$extramod" ] ; then
		sed -i -re \
			"s/(MODULES=[\\(\"])(.*)([\\)\"]\$)/\\1\\2$extramod\\3/" \
			$INSTALL_ROOT/etc/mkinitcpio.conf
	fi

	cat >>$INSTALL_ROOT/etc/locale.gen <<-EOF

		# by $OURSELVES
		de_DE.UTF-8 UTF-8
		en_DK.UTF-8 UTF-8
		en_US.UTF-8 UTF-8
		EOF

	#Now chroot into the future system
	inst-arch_chroot-helper $INSTALL_ROOT <<-EOF || return 1
		systemctl enable sshd.service

		locale-gen

		mkinitcpio -p linux
		EOF

	# We insert parameters for console to be able to use it when starting as
	# virtual machine. But it does not work when starting bare-metal:
	# kernel_parm+=" consoleblank=0 console=ttyS0,115200n8 console=tty0"
	cat >$INSTALL_ROOT/etc/kernel/cmdline <<-EOF || return 1
		${kernel_parm}
		EOF

	# Configure an autoupdate Service and timer.
	# if updatetim is blank, disable it
	printf "Configuring nafetsde-autoupdate at %s on %s\n" \
		"$updatetim" "$INSTALL_ROOT" >&2

	install-timer \
		"nafetsde-autoupdate" \
		"/bin/bash -c \"pacman -Suy --noconfirm $pkgs_ignore && systemctl reboot\"" \
		"" \
		"" \
		"*-*-* ${updatetim-1:00}" \
	|| return 1

	if [ -z "$updatetim" ] ; then
		systemctl --root $INSTALL_ROOT \
			disable nafetsde-autoupdate.timer \
		|| return 1
	fi

	return 0
}

##### Install ARM base OS ####################################################
function inst-arch_basearm {
	# Parameters:
	#    1 - hostname
	#    2 - time to run autoupdate [default=blank means disabled]
	local name="$1"
	local updatetim="$2"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	# Download latest Image
	local imgfile
	imgfile=$(util_download \
		http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-latest.tar.gz \
		) \
	|| return 1

	# Now start the installation after confirmation of the user
	printf "Installing Arch Linux ARM on %s for %s.\n" \
		"$INSTALL_ROOT" "$name" >&2

	# bsdtar complains when writing to FAT32 since it cannot put the access
	# rights. So we write boot separately with options to bsdtar to ignore
	# access rights. Be careful with the order of options, bsdtar is very
	# ugly on that.
	printf "Extracting root FS ... \n"
	bsdtar \
		--exclude=./boot \
		-f $imgfile \
		-C $INSTALL_ROOT \
		-xpz &&
	bsdtar \
		--no-fflags \
		-f $imgfile \
		-C $INSTALL_ROOT \
		-xz \
		./boot &&

	genfstab -U -p $INSTALL_ROOT >$INSTALL_ROOT/etc/fstab || return 1

	test -e $INSTALL_ROOT/etc/localtime && rm $INSTALL_ROOT/etc/localtime

	# set Hostname
	printf "%s\n" "$name" >$INSTALL_ROOT/etc/hostname &&

	# Now Set the system to German language
	# for german use: echo "LANG=de_DE.UTF-8" > /etc/locale.conf
	printf "LANG=en_DK.UTF-8" > $INSTALL_ROOT/etc/locale.conf &&
	ln -s /usr/share/zoneinfo/Europe/Berlin $INSTALL_ROOT/etc/localtime &&
	cat >>$INSTALL_ROOT/etc/locale.gen <<-EOF || return 1

		# by $OURSELVES
		de_DE.UTF-8 UTF-8
		en_DK.UTF-8 UTF-8
		EOF

	# Setup a Keyring for new system
	KEYR_DIR=/usr/share/pacman/keyrings/$(basename $INSTALL_ROOT) &&
	ln -s \
		$INSTALL_ROOT/usr/share/pacman/keyrings \
		$KEYR_DIR &&
	sed "s:Include = /:Include = $INSTALL_ROOT/:" \
		<$INSTALL_ROOT/etc/pacman.conf \
		>$INSTALL_ROOT/etc/pacman.conf.installroot
	pacman-key --init \
		--config $INSTALL_ROOT/etc/pacman.conf.installroot \
		--gpgdir $INSTALL_ROOT/etc/pacman.d/gnupg &&
	pacman-key --populate $(basename $INSTALL_ROOT)/archlinuxarm \
		--config $INSTALL_ROOT/etc/pacman.conf.installroot \
		--gpgdir $INSTALL_ROOT/etc/pacman.d/gnupg &&
	killall "gpg-agent" -u root &&
	true || return 1

	# Executing pacman fails as the hooks would executed with the wrong
	# architecture and thus fail.
	# So we dont allow additional packages here, instead they need to be
	# in stalled using ssh later once the system is up and running.
	##### Install additional requested packages
	##### PACMAN_ARGS="--arch arm" &&
	##### PACMAN_ARGS+=" --root $INSTALL_ROOT" &&
	##### PACMAN_ARGS+=" --config $INSTALL_ROOT/etc/pacman.conf.installroot" &&
	##### PACMAN_ARGS+=" --cachedir $INSTALL_ROOT/var/cache/pacman/pkg" &&
	##### PACMAN_ARGS+=" --gpgdir $INSTALL_ROOT/etc/pacman.d/gnupg" &&
	##### PACMAN_ARGS+=" --noconfirm" &&
	##### pacman $PACMAN_ARGS -Suy \
	##### pacman $PACMAN_ARGS -S --needed openssh $extrapkg \
	##### || return 1

	# Configure an autoupdate Service and timer.
	# if updatetim is blank, disable it
	printf "Configuring nafetsde-autoupdate at %s on %s\n" \
		"$updatetim" "$INSTALL_ROOT" >&2

	install-timer \
		"nafetsde-autoupdate" \
		"/bin/bash -c \"pacman -Suy --noconfirm $pkgs_ignore && systemctl reboot\"" \
		"" \
		"" \
		"*-*-* ${updatetim-1:00}" \
	|| return 1

	if [ -z "$updatetim" ] ; then
		systemctl --root $INSTALL_ROOT \
			disable nafetsde-autoupdate.timer \
		|| return 1
	fi

	return 0
}

##### create Grub Config #####################################################
function inst-arch_bootmgr-grubconfig {
	# Configure Grub for EFI or raw boot ( in /boot/grub/grub.cfg )
	printf "Configuring Grub on %s\n" "$INSTALL_ROOT" >&2

	# Install grub2 Config for booting efi or raw.
	mkdir -p $INSTALL_ROOT/boot/grub 2>/dev/null &&

	sed_cmd="s:"
	sed_cmd="${sed_cmd}GRUB_CMDLINE_LINUX=\"\(.*\)\"$:"
	sed_cmd="${sed_cmd}GRUB_CMDLINE_LINUX=\"\$(cat /etc/kernel/cmdline) \\1\":"
	sed -i.orig -e "$sed_cmd" $INSTALL_ROOT/etc/default/grub &&

	inst-arch_chroot-helper $INSTALL_ROOT <<-"EOFGRUB" &&
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
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ -z "$INSTALL_BOOT" ] ; then
		printf "%s: Error \$INSTALL_BOOT is not set\n" \
			"$FUNCNAME" >&2
		return 1
	fi

	inst-arch_bootmgr-grubconfig || return 1

	printf "Installing Grub-EFI on %s in %s\n" "$INSTALL_ROOT" "$INSTALL_BOOT" >&2

	inst-arch_chroot-helper $INSTALL_ROOT <<-EOFGRUB || return 1
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
		mkdir -p $INSTALL_ROOT/$INSTALL_BOOT/EFI/BOOT 2>/dev/null
		cp -a	$INSTALL_ROOT/$INSTALL_BOOT/EFI/arch/grubx64.efi \
			$INSTALL_ROOT/$INSTALL_BOOT/EFI/BOOT/BOOTx64.EFI \
			|| return 1

		cat >$INSTALL_ROOT/etc/systemd/system/nafetsde-efiboot.service <<-EOF || return 1
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
		systemctl --root=$INSTALL_ROOT enable nafetsde-efiboot.service
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
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	if [ -z "$rawdev" ] && [ ! -z "$INSTALL_DEV" ] ; then
		rawdev="$INSTALL_DEV"
		printf "Autoproved Raw Device to INSTALL_DEV=%s\n" "$rawdev" >&2
	elif [ -z "$rawdev" ] ; then
		rawdev=$(cat /proc/mounts \
			| grep "$INSTALL_ROOT " \
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

	inst-arch_chroot-helper $INSTALL_ROOT <<-EOF || return 1
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
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ -z "$INSTALL_BOOT" ] ; then
		printf "%s: Error \$INSTALL_BOOT is not set\n" \
			"$FUNCNAME" >&2
		return 1
	elif [ ! -w $INSTALL_ROOT/etc/mkinitcpio.d/linux.preset ] ; then
		printf "%s: Error %s  does not exist or ist not writable\n" \
			"$FUNCNAME"  "/etc/mkinitcpio.d/linux.preset" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	cat >>$INSTALL_ROOT/etc/mkinitcpio.d/linux.preset <<-EOF &&
		default_efi_image="$INSTALL_BOOT/EFI/Linux/archlinux-linux.efi"
		default_options="-A systemd"
		fallback_efi_image="$INSTALL_BOOT/EFI/Linux/archlinux-linux-fallback.efi"
		fallback_options="-S autodetect -A systemd"

		ALL_microcode=(/boot/*-ucode.img)
		EOF

	touch $INSTALL_ROOT/etc/kernel/cmdline
	arch-chroot $INSTALL_ROOT bootctl install --no-variables &&
	arch-chroot $INSTALL_ROOT mkinitcpio -p linux &&
	systemctl enable systemd-boot-update.service &&
	true || return 1

	return 0
}

#### inst-arch_add_repo ######################################################
function inst-arch_add_repo () {
	local readonly PACCONF=$INSTALL_ROOT/etc/pacman.conf
	repo="$1"
	srv="${2:-"MIRROR"}"
	sig="$3"

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -w $PACCONF ] ; then
		printf "%s: Error /etc/pacman.conf does not exist or ist not writable\n" \
			"$FUNCNAME"  >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	printf "[%s]\n" "$repo" >>$PACCONF
	if [ ! -z "$sig" ] ; then
		printf "SigLevel = %s\n" "$sig" >>$PACCONF || return 1
	fi

	for f in $srv ; do
		if [ "$f" == "MIRROR" ] ; then
			printf "Include = /etc/pacman.d/mirrorlist\n" \
				>>$PACCONF || return 1
		else
			printf "Server = %s\n" "$f" >>$PACCONF || return 1
		fi
	done

	#----- Closing -------------------------------------------------------
	printf "Added ArchLinux Repo %s" >&2
	[ -z "$sig" ] || printf " (SigLevel %s)" "$sig" >&2
	[ -z "$srv" ] || printf " (Srv %s)" "$srv" >&2
	printf "\n"

	return 0
}

#### inst-arch_fixverpkg #####################################################
function inst-arch_fixverpkg () {
	local readonly PACCONF=$INSTALL_ROOT/etc/pacman.conf
	pkgs="$@"

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -z "${PKGBASE/*:*/}" ] && [ ! -d $PKGBASE ] ; then
		printf "%s: Error PKGBASE %s does not exist\n" \
			"$FUNCNAME" "$PKGBASE" >&2
	elif [ ! -w $PACCONF ] ; then
		printf "%s: Error /etc/pacman.conf does not exist or ist not writable\n" \
			"$FUNCNAME"  >&2
		return 1
	elif ! grep "IgnorePkg" $PACCONF ; then
		printf "%s: Error /etc/pacman.conf does not contain IgnorePkg\n" \
			"$FUNCNAME"  >&2
		return 1
	elif [ ! -x "$INSTALL_ROOT/usr/bin/pacconf" ] ; then
		printf "%s: Error /usr/bin/pacconf does not exist or ist not executable\n" \
			"$FUNCNAME"  >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	local arch PKGDIR pkg pkgfile pkgnames pkgslocal
	arch=$(arch-chroot $INSTALL_ROOT /usr/bin/pacconf |
		sed -n 's/Architecture[[:blank:]]*=[[:blank:]]*//p') &&
	printf "Arch=%s\n" "$arch" &&
	PKGDIR="$PKGBASE/community/os/$arch" &&
	true || return 1

	pkgnames=""
	pkgslocal=""

	for pkg in $pkgs ; do
		pkgfile=$(util_make-local "$PKGDIR/$pkg-$arch.pkg.tar.zst") ||
		pkgfile=$(util_make-local "$PKGDIR/$pkg-any.pkg.tar.zst") ||
		pkgfile=$(util_make-local "$PKGDIR/$pkg-$arch.pkg.tar.xz") ||
		pkgfile=$(util_make-local "$PKGDIR/$pkg-any.pkg.tar.xz") ||
		pkgfile=""

		if [ -z "$pkgfile" ] ; then
			printf "Error: Package file %s not found.\n" "$PKGDIR/$pkg-{$arch,any}.pkg.tar.{zst,xz}"
			return 1
		fi

		pkgnames+=" $(pacman -Qp $pkgfile | cut -d" " -f 1)" &&
		pkgslocal+=" /root/$(basename $pkgfile)" &&
		cp -a $pkgfile $INSTALL_ROOT/root/ &&
		true || return 1
	done
	arch-chroot $INSTALL_ROOT \
		pacman -U --needed --noconfirm $pkgslocal &&
	sed -i "s/#* *IgnorePkg *= *\(.*\)$/IgnorePkg =$pkgnames \1/" \
		$PACCONF &&
	true || return 1

	#----- Closing -------------------------------------------------------
	printf "Added Package(s) with fixed version %s\n" "$pkgs" >&2

	return 0
}

##### main ####################################################################

# do nothing
