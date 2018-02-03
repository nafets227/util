#!/bin/bash
#
# install-functions.sh
#
# Collection of install-related functions. Specific functinos are places in
# different files, one for each operating system like Archlinux or CoreOS
#
# (C) 2018 Stefan Schallenberg
#


#### Install our special files on machine ####################################
function install_nafets_files {
	local readonly name="$1"
	local readonly mount="${2-$INSTALL_ROOT}"

	if [ $# -ne 1 ] ; then
		printf "Internal Error: %s got %s parms (exp=1+)\n" \
			"$FUNCNAME" "$#" >&2
		return 1
	elif [ -z "$name" ] ; then
		printf "Internal Error: Parm1 is null in %s \n" \
			"$FUNCNAME" >&2
		return 1
	elif [ ! -d "$mount" ] ; then
		printf "Internal Error: Directory %s does not exist in %s \n" \
			"$mount" "$FUNCNAME" >&2
		return 1
	fi

	# on error return 1
	trap "trap '' ERR; return 1" ERR

	# Copy SSL private files
	if [ -d /data/ca/$name ]; then
		mkdir -p $mount/root/ssl.private
		cp -L  /data/ca/$name/* $mount/root/ssl.private/
		chown -R root:root $mount/root/ssl.private
		chmod -R 400 $mount/root/ssl.private
		printf "INSTALLED SSL Files\n" >&2
	fi

	#Get SubVersion Repository
	svn checkout \
		--username root@$name \
		--password "" \
		--non-interactive \
		--quiet \
		--config-dir $mount/root/.subversion \
	        --config-option servers:global:store-plaintext-passwords=yes \
	        svn://svn.intranet.nafets.de/tools/trunk \
		$mount/root/tools
	printf "INSTALLED subversion repository\n" >&2

	# Copy local modified files to new machine
	rsync -aHX --delete /root/tools/ $mount/root/tools --exclude=".svn"
	printf "UPDATED subversion repository\n" >&2

	trap '' ERR

	return 0
}

#### Install a service that runs additional installations after first boot ###
function install_setup_service () {
	# Parameter:
	#    1 - mounted_rootdir
	#    2 - Install type - matches to /root/install/install-<type>.sh
	#        that will be called on first boot
	if [ ! -d $1/etc/systemd/system ] ; then
		printf "Internal Error: %s is not a directory.\n" \
			"$1/etc/systemd/system" >&2
		return 1
	elif [ ! -e $1/root/tools/install/install-$2.sh ] ; then
		printf "Warning: Skipping Install-service (no %s).\n" \
			"$1/root/tools/install/install-$2.sh" >&2
		return 0
	fi
	printf "Installing Install-Service for machine type %s.\n" "$2" >&2
	cat >>$1/etc/systemd/system/nafetsde-install.service <<-EOF
		# nafetsde-install.service
		#
		# (C) 2017 Stefan Schallenberg
		#
		[Unit]
		Description="Install $2 machine after first boot (nafets.de)"
		ConditionPathExists=!/var/lib/nafetsde-install/.done

		[Service]
		Type=oneshot
		ExecStart=/root/tools/install/install-$2.sh
		ExecStartPost=/root/tools/install/install.sh install_env_expire_std_root_pw
		ExecStartPost=/bin/mkdir -p /var/lib/nafetsde-install
		ExecStartPost=/bin/touch /var/lib/nafetsde-install/.done

		[Install]
		WantedBy=multi-user.target
		EOF
		
	arch-chroot $1 <<-EOF
		systemctl enable nafetsde-install.service
	EOF

}


##### install_ssl_sshtrust ###################################################
function install_allow-root-pw {

 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif fgrep "nafets.de" $INSTALL_ROOT/etc/ssh/sshd_config >/dev/null ; then
		# avoid to add this configuration a second time
		printf "Setting up SSH Root Access with Password skipped.\n"
		return 0
	fi
 	
	#----- Real Work -----------------------------------------------------
	cat >>$INSTALL_ROOT/etc/ssh/sshd_config <<-"EOF"

		# SSH config modification
		# nafets.de by util/install-functions.sh
		PermitRootLogin yes
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Root Access with Password completed.\n"

	return 0
}


##### install_easeofuse ######################################################
function install_ease-of-use {
 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	cat >$INSTALL_ROOT/etc/profile.d/nafets_de.sh <<-"EOF"
		#!/bin/sh
		#
		# (C) 2014-2018 Stefan Schallenberg

		test "$BASH" || return

		export LS_OPTIONS='--color=auto'
		alias l='ls $LS_OPTIONS -la'
		eval "`dircolors`"
		export EDITOR="vim"
		EOF
	chmod 755 $INSTALL_ROOT/etc/profile.d/nafets_de.sh

	# Enable Syntax highlighting in vim
	arch-chroot $INSTALL_ROOT <<-"EOF"
		pacman -S --needed --noconfirm vim vim-systemd
		EOF

	fgrep "syntax enable" $INSTALL_ROOT/etc/vimrc >/dev/null || \
		printf "syntax enable\n" >>$INSTALL_ROOT/etc/vimrc

	#----- Closing  ------------------------------------------------------
	printf "Setting up Environment completed.\n"

	return 0
}

#### Install Nafets Standards ################################################
function install_nafets-std {
	# SSL Zertifikat der eigenen CA installieren.
#	install_ssl_ca
	# Root logon in SSH erlauben
	install_allow-root-pw && 
	install_ease-of-use

	return $?
}

##### Main ###################################################################

# Load Sub.Modules
for f in $(dirname $BASH_SOURCE)/install/*.sh ; do
	echo "Loading Module $f"
	. $f
done

