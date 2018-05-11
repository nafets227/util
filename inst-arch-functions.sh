#! /bin/bash
#
# inst-arch-functgion.sh
#
# Install helper functions for Arch Linux
#
# (C) 2014-2018 Stefan Schallenberg
#

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

	#install needed utilities
	pacman -S --needed --noconfirm arch-install-scripts dosfstools >&2

	# create tempdir to temporary mount the filesystems
	INSTALL_ROOT=$(mktemp --directory --tmpdir inst-arch.XXXXXXXXXX)
	[ $? -ne 0 ] && return 1

	# Important: export INSTALL_ROOT now to let the caller do cleanup with
	# the funtion inst-arch_finalize
	export INSTALL_ROOT

	# Create root Filesystems and mount it
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

	arch-chroot $INSTALL_ROOT <<-EOF
		passwd -e root
	EOF

	umount --recursive --detach-loop "$INSTALL_ROOT"
	unset INSTALL_ROOT

	return 0
}

##### Install Arch Linux on a new filesystem #################################
function inst-arch_baseos {
	# Parameters:
	#    1 - hostname
	#    3 - additional package [optionsal]
	#    4 - additional Modules in initrd [optional]
	local name="$1"
	local extrapkg="$2"
	local extramod="$3"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	printf "Installing Arch Linux on %s for %s. \n\tExtra Packages: %s\n\tExtra Modules: %s\n" \
		"$INSTALL_ROOT" "$name" "$extrapkg" "$extramod" >&2

	#Bootstrap the new system
	pacstrap -c -d $INSTALL_ROOT base openssh $extrapkg || return 1
	genfstab -U -p $INSTALL_ROOT >$INSTALL_ROOT/etc/fstab || return 1

	# Now include the needed modules in initcpio
	if [ ! -z "$extramod" ] ; then
		sed -i -re \
			"s/(MODULES=[\\(\"])(.*)([\\)\"]\$)/\\1\\2$extramod\\3/" \
			$INSTALL_ROOT/etc/mkinitcpio.conf
	fi

	# set Hostname
	printf "%s\n" "$name" >$INSTALL_ROOT/etc/hostname

	# Now Set the system to German language
	# for german use: echo "LANG=de_DE.UTF-8" > /etc/locale.conf
	printf "LANG=en_DK.UTF-8" > $INSTALL_ROOT/etc/locale.conf
	echo "KEYMAP=de-latin1-nodeadkeys"  > $INSTALL_ROOT/etc/vconsole.conf
	test -e $INSTALL_ROOT/etc/localtime && rm $INSTALL_ROOT/etc/localtime
	ln -s /usr/share/zoneinfo/Europe/Berlin $INSTALL_ROOT/etc/localtime
	cat >>$INSTALL_ROOT/etc/locale.gen <<-EOF

		# by $OURSELVES
		de_DE.UTF-8 UTF-8
		en_DK.UTF-8 UTF-8
		EOF

	#Now chroot into the future system
	arch-chroot $INSTALL_ROOT <<-EOF || return 1
		systemctl enable sshd.service

		locale-gen

		mkinitcpio -p linux

		#Root Passwort aendern
		printf "Forst2000\nForst2000\n" | passwd
		EOF

	# Concfigure Grub for both XEN ( in /boot/grub/grub.cfg) and
	# EFI or raw boot ( in /boot/grub2/grub/grub.cfg )
	printf "Configuring Grub on %s\n" "$INSTALL_ROOT" >&2

	# Install grub.cfg for XEN booting.
	# This is a minimum file to serve as input for pygrub during
	# XEN loading of image.
	mkdir -p $INSTALL_ROOT/boot/grub 2>/dev/null
	cat >$INSTALL_ROOT/boot/grub/grub.cfg <<-EOFGRUB || return 1
		# by $OURSELVES
		menuentry 'Arch Linux for XEN pygrub' {
		    set root='hd0,msdos1'
		    echo    'Loading Linux core repo kernel ...'
		    linux   /boot/vmlinuz-linux root=/dev/xvda1 ro
		    echo    'Loading initial ramdisk ...'
		    initrd  /boot/initramfs-linux.img
		}
		EOFGRUB

	# Install grub2 Config for booting efi or raw.
	# We insert parameters for console to be able to use it
	# when starting as virtual machine.
	mkdir -p $INSTALL_ROOT/boot/grub2/grub 2>/dev/null
        # does not work when starting bare-metal: 
	# kernel_parm="consoleblank=0 console=ttyS0,115200n8 console=tty0"
        sed_cmd="s:"
        sed_cmd="${sed_cmd}GRUB_CMDLINE_LINUX=\"\(.*\)\"$:"
        sed_cmd="${sed_cmd}GRUB_CMDLINE_LINUX=\"${kernel_parm}\\1\":p"
	sed -i.orig -e "$sed_cmd" $INSTALL_ROOT/etc/default/grub
	#cat >>$INSTALL_ROOT/etc/default/grub <<-EOF
	#
	#	## Serial console
	#	## by $OURSELVES
	#	GRUB_TERMINAL=serial
	#	GRUB_SERIAL_COMMAND="serial --speed=38400 --unit=0 --word=8 --parity=no --stop=1"
	#	EOF
	#
	arch-chroot $INSTALL_ROOT <<-"EOFGRUB" || return 1
		grub-mkconfig >/boot/grub2/grub/grub.cfg || exit 1
		EOFGRUB


	return 0
}

##### Install Grub for efi ###################################################
function inst-arch_bootmgr-grubefi {
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	printf "Installing Grub-EFI on %s\n" "$INSTALL_ROOT" >&2

	arch-chroot $INSTALL_ROOT <<-"EOFGRUB" || return 1
		pacman -S --needed --noconfirm grub efibootmgr || exit 1
		grub-install \
			--target=x86_64-efi \
			--boot-directory=/boot/grub2 \
			--efi-directory=/boot/efi/ \
			--no-bootsector \
			--no-nvram \
			|| exit 1
		EOFGRUB

	# Bugfix EFI buggy BIOS - will be redone by systemd ervice
	# nafetsde-efiboot on each shutdown
	mkdir -p $INSTALL_ROOT/boot/efi/EFI/BOOT 2>/dev/null
	cp -a	$INSTALL_ROOT/boot/efi/EFI/arch/grubx64.efi \
		$INSTALL_ROOT/boot/efi/EFI/BOOT/BOOTx64.EFI \
		|| return 1

	cat >$INSTALL_ROOT/etc/systemd/system/nafetsde-efiboot.service <<-"EOF" || return 1
		# nafetsde-efiboot.service
		#
		# (C) 2015 Stefan Schallenberg
		#
		[Unit]
		Description="efiboot Updates on Shutdown for Buggy EFI-BIOS"

		[Service]
		Type=oneshot
		RemainAfterExit=yes
		ExecStop=/usr/bin/cp -a /boot/efi/EFI/arch/grubx64.efi /boot/efi/EFI/BOOT/BOOTx64.EFI

		[Install]
		WantedBy=multi-user.target
		EOF
	systemctl --root=$INSTALL_ROOT enable nafetsde-efiboot.service

	return 0
}

##### Install Grub for efi ###################################################
function inst-arch_bootmgr-grubraw {
	# Parameters:
	#    1 - rawdev [optional, autoprobed to device of INSTALL_ROOT]
	local rawdev="$1"

	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	if [ -z "$rawdev" ] ; then
		rawdev=$(cat /proc/mounts \
		       | grep "$INSTALL_ROOT " \
		       | cut -d" " -f 1)
		printf "Autoprobed Raw Device to %s\n" "$rawdev" >&2
	fi

	if [ ! -b "$rawdev" ] ; then
		printf "Raw Device %s is no block device.\n" "$rawdev" >&2
		return 1
	fi

	printf "Installing Grub-Raw on %s (%s)\n" "$INSTALL_ROOT" "$rawdev" >&2

	arch-chroot $INSTALL_ROOT <<-EOF || return 1
		pacman -S --needed --noconfirm grub || exit 1
		grub-install \\
			--target=i386-pc \\
			--boot-directory=/boot/grub2 \\
			$rawdev \\
			|| exit 1
	EOF

	return 0
}

#### inst-arch_add_repo ######################################################
function inst-arch_add_repo () {
	local readonly PACCONF=$INSTALL_ROOT/etc/pacman.conf
	repo="$1"
	srv="$2"
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
	if [ -z "$srv" ] ; then
		printf "Include = /etc/pacman.d/mirrorlist\n" \
			>>$PACCONF || return 1
	else
		for f in $srv ; do
			printf "Server = %s\n" "$f" >>$PACCONF || return 1
		done
	fi

	#----- Closing -------------------------------------------------------
	printf "Added ArchLinux Repo %s" >&2
	[ -z "$sig" ] || printf " (SigLevel %s)" "$sig" >&2
	[ -z "$srv" ] || printf " (Srv %s)" "$srv" >&2
	printf "\n"

	return 0
}

##### main ####################################################################

# do nothing

