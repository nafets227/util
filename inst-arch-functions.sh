#! /bin/bash
#
# inst-arch-functgion.sh
#
# Install helper functions for Arch Linux
#
# (C) 2014-2018 Stefan Schallenberg
#

#### Install Arch Linux on a mounted directory ###############################
function inst-arch_ondir () {
# Parameters: 
#    1 - hostname
#    2 - mounted_rootdir
#    3 - extra packages to install [optional]
#    4 - machine type [default=xen]
#    5 - bootdevice to install bootloader (if machtype=kvm or phys)
#    6 - install type - start install-<type> script after boot
#
# see also http://www.zdnet.de/41559191/multiboot-ueber-usb-nur-ein-stick-fuer-windows-und-linux/2/

machtype=${4-xen}

case $machtype in
	xen)
		newmods="xen-blkfront xen-fbfront xen-netfront xen-kbdfront" # XEN drivers
		machboot=grubcfg
		;;
	kvm)
		newmods="ata_generic ata_piix pata_acpi "					 # KVM neede drv
		newmods="$newmods virtio_blk virtio_console virtio_pci"		 # KVM drivers
		machboot=grub2
		;;
	phys)
		newmods="xen-blkfront xen-fbfront xen-netfront xen-kbdfront" # XEN drivers
		newmods="$newmods ehci_pci xhci_pci ahci"					 # HW drivers
		machboot="grub2 grubcfg grub2-efi"
		;;
	usb)
		# grub2-efi does not work yet so we disable it.
		# @TODO: make grub2-efi work on USB Stick
		# Msg: grub-install: error: failed to get canonical path of /boot/efi
		machboot="grub2"
		;;
	*)
		printf "Unknown machine type %s in %s\n" "$machtype" "$FUNCNAME" >&2
		return 1
esac

#Now chroot into the Arch Bootstrap system
pacstrap -c -d $2 base openssh subversion $3
rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

genfstab -U -p $2 >$2/etc/fstab
rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi

#Now chroot into the future system
arch-chroot $2 <<EOF
    echo $1 >/etc/hostname
    systemctl enable sshd.service

    # Now Set the system to German language
    # for german use: echo "LANG=de_DE.UTF-8" > /etc/locale.conf
    echo "LANG=en_DK.UTF-8" > /etc/locale.conf
    echo "KEYMAP=de-latin1-nodeadkeys"  > /etc/vconsole.conf
    test -e /etc/localtime && rm /etc/localtime
    ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    echo "de_DE.UTF-8 UTF-8" >>/etc/locale.gen
    echo "en_DK.UTF-8 UTF-8" >>/etc/locale.gen
    locale-gen

    if [ "$machtype" == "phys" ]; then
        sed -i -r \
            -e 's:^[[:blank:]]md_component_detection = 1:\t#&\n\tmd_component_detection = 0 # by create-vm-image:' \
            -e 's:^.*# global_filter = .*:&\n\tglobal_filter = [ "a|^/dev/sd|", "a|^/dev/xvd|", "r|.*/|" ] # by create-vm-image:' \
            /etc/lvm/lvm.conf
    fi

    # Now include the needed modules in initcpio
    sed -i -re \
	's/(MODULES=[\("])(.*)([\)"]$)/\1\2$newmods\3/' \
        /etc/mkinitcpio.conf
    mkinitcpio -p linux
    
    #Root Passwort aendern
    (echo "Forst2000"; echo "Forst2000") | passwd
EOF

install_nafets_files "$1" "$2"

for f in $machboot ; do case "$f" in
	grubcfg) 
		printf "Installing GrubCFG\n"    
		#GRUB Config Files
		mkdir -p $2/boot/grub 2>/dev/null
	 	cat >$2/boot/grub/grub.cfg <<-EOFGRUB
			menuentry 'Arch Linux for XEN pygrub' {
			    set root='hd0,msdos1'
			    echo    'Loading Linux core repo kernel ...'
			    linux   /boot/vmlinuz-linux root=/dev/xvda1 ro 
			    echo    'Loading initial ramdisk ...'
			    initrd  /boot/initramfs-linux.img
			}
			EOFGRUB
		;;
	grub2)
		printf "Installing Grub2\n"
		if [ -z "$5" ] ; then
			printf "Internal error: Missing parameter 5 (bootdevice).\n"
			return 1
		fi
		arch-chroot $2 <<-EOF
			pacman -S --needed --noconfirm grub
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
			grub-install \\
				--target=i386-pc \\
				--boot-directory=/boot/grub2 $5
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
			grub-mkconfig >/boot/grub2/grub/grub.cfg
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
		EOF
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
		;;
	grub2-efi)
		printf "Installing Grub2\n"
		arch-chroot $2 <<-EOF
			pacman -S --needed --noconfirm grub efibootmgr
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
			grub-install \\
				--target=x86_64-efi \\
				--boot-directory=/boot/grub2 \\
				--efi-directory=/boot/efi/
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
			grub-mkconfig >/boot/grub2/grub/grub.cfg
			rc=\$? ; if [ \$rc -ne 0 ] ; then exit \$rc; fi
		EOF
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
		# Bugfix EFI buggy BIOS - will be redone by systemd ervice
		# nafetsde-efiboot on each shutdown
		mkdir -p $2/boot/efi/EFI/BOOT
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
		cp -a	$2/boot/efi/EFI/arch/grubx64.efi \
			$2/boot/efi/EFI/BOOT/BOOTx64.EFI
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
		;;
	 *)
	 	printf "Internal Error: Invalid machboot \"%s\"\n" "$f" >&2
esac; done

if [ -z "$6" ] ; then
	arch-chroot $2 <<-EOF
		passwd -e root
	EOF
	echo "Remember to setup up networking in the new machine, its not done yet!" 
else
	install_setup_service "$2" "${6,,}"
	rc=$? ; if [ $rc -ne 0 ] ; then return $rc; fi
fi

return 0
}


#### Install Arch Linux ######################################################
function inst-arch_do() {
# Parameters: 
#    1 - hostname
#    2 - rootdev
#    3 - extra packages to install [optional]
#    4 - boot device [optional]
#    5 - physical machine [default=no]
#    6 - install type - start install-<type> script after boot

is_phys=${5-0}
echo "About to install Arch Linux for $1 (phys=$is_phys, type=$6)"
echo "Extra packages: $3"
if [ -z $4 ]; then
	echo "Root-Device: $2"
	echo "Warning: All data on $2 will be DELETED!"
else
	echo "Root-Device: $2, Boot-Device: $4"
	echo "Warning: All data on $2 and $4 will be DELETED!"
fi
read -p "Press Enter to Continue, use Ctrl-C to break."

#install needed utilities
pacman -S --needed --noconfirm arch-install-scripts dosfstools

# Create Filesystems
mkfs.ext4 $2
if [ $? -ne 0 ] ; then exit -1; fi
mount $2 /mnt

if [ ! -z $4 ]; then
	mkfs.fat -F32 $4
	if [ $? -ne 0 ] ; then exit -1; fi
	mkdir -p /mnt/boot/efi
	mount $4 /mnt/boot/efi
fi

if [ "$is_phys" == "0" ] ; then 
	machtype="xen"
else
	machtype="phys"
fi
	
inst-arch_ondir "$1" "/mnt" "$3" "$machtype" "" $itype

if [ ! -z $4 ]; then
    umount /mnt/boot/efi
fi
umount /mnt
}

#### Install Arch Linux for KVM, in a Device as disk ########################
function inst-arch_do_kvm () {
	# Parameters: 
	#    1 - hostname
	#    2 - device
	#    3 - extra packages to install [optional]
	#    4 - install type - start install-<type> script after boot

	inst_hostname="$1"
	inst_dev="$2"
	inst_extrapkg="$3"
	itype="$4"
	
	printf "About to install Arch Linux on KVM for %s (type=%s)\n" \
	       	"$inst_hostname" "$itype"
	printf "Extra packages: %s\n" "$inst_extrapkg"
	printf "Disk-Device: %s\n" "$inst_dev"
	printf "Warning: All data on %s will be DELETED!\n" "$inst_dev"
	read -p "Press Enter to Continue, use Ctrl-C to break."

	#install needed utilities
	pacman -S --needed --noconfirm arch-install-scripts dosfstools rsync

	if [ ! -e "$inst_dev" ] ; then
		printf "Creating Bootdevice %s (size=10G)\n" "$inst_dev"
		fallocate -l 10G $inst_dev
		if [ $? -ne 0 ] ; then
			printf "Falling back to dd since fallocate is not working.\n" >&2
			dd if=/dev/zero of=$inst_dev bs=1M count=10240
			if [ $? -ne 0 ] ; then return -1; fi
		fi
	fi

	parted -s -- "$inst_dev" mklabel msdos
	if [ $? -ne 0 ] ; then return -1; fi
	parted -s -- "$inst_dev" mkpart primary ext4 100M -1s
	if [ $? -ne 0 ] ; then return -1; fi

	part=$(kpartx -asv "$(realpath "$inst_dev")" | \
		sed -n -e 's:^add map \([A-Za-z0-9\-]*\).*:\1:p')
	if [ $? -ne 0 ] || [ -z "$part" ] ; then return -1; fi
	
	# delete superblock to avoid warning when creating the new filesystem
	dd if=/dev/zero of=/dev/mapper/$part bs=1k count=4 
	mkfs.ext4 /dev/mapper/$part
	if [ $? -ne 0 ] ; then return -1; fi
	
	mount /dev/mapper/$part /mnt
	if [ $? -ne 0 ] ; then return -1; fi
	
	inst-arch_ondir "$inst_hostname" "/mnt" "$inst_extrapkg" "kvm" "/dev/${part%%p1}" $4
	rc=$?		

	#umount /mnt/boot
	umount /mnt
	kpartx -d "$(realpath "$inst_dev")"
	
	return $rc
}

##### main ####################################################################

# do nothing

