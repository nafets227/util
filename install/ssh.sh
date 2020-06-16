#!/bin/bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### Configuration ##########################################################
if [ "${HOSTNAME:0:4}" == "phys" ] ; then
	readonly INSTALL_SSH_SOURCE="/data/ca/private-ssh"
else
	readonly INSTALL_SSH_SOURCE="phys.intranet.nafets.de:/data/ca/private-ssh"
fi

##### install-ssh_getUserData ################################################
function install-ssh_getUserData {
	user="$1"
	
	if [ "$#" != "1" ] ; then
		printf "%s: Internal Error. Got %s parameters (Exp=1)\n" \
			"$FUNCNAME" "$#" >&2
		return 1
	fi

	passwd=$(grep "^$user:" <$INSTALL_ROOT/etc/passwd)
	rc=$?
	if [ "$rc" != "0" ] ; then
		printf "%s: Error %s finding user %s in /etc/passwd\n" \
			"$FUNCNAME" "$rc" "$user" >&2
		return 1
	elif [ -z "$passwd" ] ; then
		printf "%s: user %s not found in /etc/passwd\n" \
			"$FUNCNAME" "$user" >&2
		return 1
	fi
	
	IFS=":" read -a passwd_a <<<$passwd
	# Field 0 is username
	# Field 1 is password, not exposed for security reasons
	INSTSSH_UID="${passwd_a[2]}"
	INSTSSH_GID="${passwd_a[3]}"
	# Field 4 is User Name or comment
	INSTSSH_HOME="${passwd_a[5]}"
	# Field 6 is optional user command interpreter
	
	return 0
}

##### install-ssh_allow-root-pw ##############################################
function install-ssh_allow-root-pw {

 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif fgrep "nafets.de" $INSTALL_ROOT/etc/ssh/sshd_config >/dev/null ; then
		# avoid to add this configuration a second time
		printf "Setting up SSH Root Access with Password skipped.\n" >&2
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

##### install-ssh_trust ######################################################
function install-ssh_trust {
	fname="$1"
	user="${2:-root}"
	[[ $fname != */* ]] && fname="$INSTALL_SSH_SOURCE/$fname"
	
 	#----- Input checks --------------------------------------------------
	if [ "$#" -lt "1" ] ; then
		printf "Internal Error: %s got %s parms (exp=1+)\n" \
			"$FUNCNAME" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -z "${fname/*:*/}" ] && [ ! -r "$fname" ] ; then
		printf "%s: Error File %s does not exist or ist not readable.\n" \
			"$FUNCNAME" "$fname" >&2
		return 1
	fi
 	
	#----- Real Work -----------------------------------------------------
	install-ssh_getUserData "$user" || return 1
	
	install -o $INSTSSH_UID -g $INSTSSH_GID \
		-d -m 700 $INSTALL_ROOT$INSTSSH_HOME/.ssh && \
	install -o $INSTSSH_UID -g $INSTSSH_GID \
		-d -m 700 $INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d && \
	/bin/true || return 1

	if [ ! -z "${fname/*:*/}" ] ; then
		install -o $INSTSSH_UID -g $INSTSSH_GID -m 600 $fname \
			$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d &&
		/bin/true || return 1
	else
		scp $fname /tmp/$(basename $fname) &&
		install -o $INSTSSH_UID -g $INSTSSH_GID -m 600 \
			/tmp/$(basename $fname) \
			$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d &&
		rm /tmp/$(basename $fname) && \
		/bin/true || return 1
	fi

	cat $INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d/* \
		>$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys || \
	return 1

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Trust from %s to %s completed.\n" \
		"$fname" "$user" >&2
	
	return 0
}

##### install-ssh_key ########################################################
function install-ssh_key {
	fname="$1"
	user="${2:-root}"
	[[ $fname != */* ]] && fname="$INSTALL_SSH_SOURCE/$fname"

 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif [ ! -z "${fname/*:*/}" ] && [ ! -r "$fname" ] ; then
		printf "%s: Error File %s does not exist or ist not readable.\n" \
			"$FUNCNAME" "$fname" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	install-ssh_getUserData "$user" || return 1
	
	install -o $INSTSSH_UID -g $INSTSSH_GID \
		-d -m 700 $INSTALL_ROOT$INSTSSH_HOME/.ssh && 
	if [ ! -z "${fname/*:*/}" ] ; then
		install -o $INSTSSH_UID -g $INSTSSH_GID -m 600 $fname \
			$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa &&
		/bin/true || return 1
	else
		scp $fname /tmp/$(basename $fname) &&
		install -o $INSTSSH_UID -g $INSTSSH_GID -m 600 /tmp/$(basename $fname) \
			$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa &&
		rm /tmp/$(basename $fname) &&
		/bin/true || return 1
	fi
	
	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Key %s for %s completed.\n" "$fname" "$user" >&2
	
	return 0
}

#### install-ssh_remove-known-host ###########################################
function install-ssh_remove-known-host {
	host="$1"

	ssh-keygen -R "$host"

	return $?
}
