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
function install_ssl-private-keys {
	hostname=$(cat $INSTALL_ROOT/etc/hostname)

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -r $INSTALL_ROOT/etc/hostname ] ; then
		printf "%s: Error hostname not set in %s\n" \
			"$FUNCNAME" "$INSTALL_ROOT/etc/hostname" >&2
	elif [ -z "$hostname" ] ; then
		printf "%s: Error hostname empty in %s\n" \
			"$FUNCNAME" "$INSTALL_ROOT/etc/hostname" >&2
	fi

	#----- Real Work -----------------------------------------------------
	hostname=$(cat $INSTALL_ROOT/etc/hostname)
	# Copy SSL private files
	if [ -d /data/ca/$hostname/ ]; then
		mkdir -p $INSTALL_ROOT/root/ssl.private &&
		cp -L  /data/ca/$hostname/* $INSTALL_ROOT/root/ssl.private/ &&
		chown -R root:root $INSTALL_ROOT/root/ssl.private &&
		chmod -R 400 $INSTALL_ROOT/root/ssl.private
		rc=$?
	else
		empty=yes
		rc=0
	fi

	#----- Closing  ------------------------------------------------------
	if [ $rc != "0" ] ; then
		printf "Error installing private SSL Keys\n"
		return 1
	elif [ ! -z $empty ] ; then
		printf "Warning: No private SSL Keys found.\n"
	else
		printf "Private SSL Keys installed.\n"
	fi

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
	if \
		[ -e $INSTALL_ROOT/etc/vimrc ]  &&
		! fgrep "syntax enable" $INSTALL_ROOT/etc/vimrc >/dev/null
	then
		printf "syntax enable\n" >>$INSTALL_ROOT/etc/vimrc
	fi

	#----- Closing  ------------------------------------------------------
	printf "Setting up Environment completed.\n"

	return 0
}

##### Install Infos of scripts used to install ###############################
function install_instinfo {
	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	git log -n 1 >$INSTALL_ROOT/root/instinfo.gitrev
	git diff HEAD >$INSTALL_ROOT/root/instinfo.gitdiff

	#----- Closing  ------------------------------------------------------
	printf "Noted script revision to /root/instinfo.*\n"

	return 0
}

#### Install Nafets Standards ################################################
function install_nafets-std {
	# SSL Zertifikat der eigenen CA installieren.
#	install_ssl_ca
	# Root logon in SSH erlauben
	install-ssh_allow-root-pw && 
	install_ssl-private-keys &&
	install_ease-of-use && 
	install_instinfo

	return $?
}

##### Main ###################################################################

# Load Sub.Modules
for f in $(dirname $BASH_SOURCE)/install/*.sh ; do
	echo "Loading Module $f"
	. $f
done

