#!/usr/bin/env bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### install-ssh_getUserData ################################################
function install-ssh_getUserData {
	user="$1"

	if [ "$#" != "1" ] ; then
		printf "%s: Internal Error. Got %s parameters (Exp=1)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	fi

	passwd=$(grep "^$user:" <"$INSTALL_ROOT/etc/passwd")
	rc=$?
	if [ "$rc" != "0" ] ; then
		printf "%s: Error %s finding user %s in /etc/passwd\n" \
			"${FUNCNAME[0]}" "$rc" "$user" >&2
		return 1
	elif [ -z "$passwd" ] ; then
		printf "%s: user %s not found in /etc/passwd\n" \
			"${FUNCNAME[0]}" "$user" >&2
		return 1
	fi

	IFS=":" read -r -a passwd_a <<<"$passwd"
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
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif grep -F "nafets.de" "$INSTALL_ROOT/etc/ssh/sshd_config" >/dev/null ; then
		# avoid to add this configuration a second time
		printf "Setting up SSH Root Access with Password skipped.\n" >&2
		return 0
	fi

	#----- Real Work -----------------------------------------------------
	cat >>"$INSTALL_ROOT/etc/ssh/sshd_config" <<-"EOF"

		# SSH config modification
		# nafets.de by util/install-functions.sh
		PermitRootLogin yes
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Root Access with Password completed.\n"

	return 0
}

##### install-ssh_allow-env ##################################################
function install-ssh_allow-env {

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif grep -F "nafetsde-sshenv" "$INSTALL_ROOT/etc/ssh/sshd_config" >/dev/null ; then
		# avoid to add this configuration a second time
		printf "Setting up SSH Environment Config skipped.\n" >&2
		return 0
	fi

	#----- Real Work -----------------------------------------------------
	cat >>"$INSTALL_ROOT/etc/ssh/sshd_config" <<-"EOF"

		# SSH config modification nafetsde-sshenv
		# nafets.de by physerver/install install-ssh_allow-env
		PermitUserEnvironment yes
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Environment Config completed.\n"

	return 0
}

##### install-ssh_trust ######################################################
function install-ssh_trust {
	fname="$1"
	user="${2:-root}"
	lfname="${3:-$(basename "$fname")}"
	parms="$4"

	#----- Input checks --------------------------------------------------
	# jscpd:ignore-start
	if [ "$#" -lt "1" ] ; then
		printf "Internal Error: %s got %s parms (exp=1+)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -n "${fname/*:*/}" ] && [ ! -r "$fname" ] ; then
		printf "%s: Error File %s does not exist or ist not readable.\n" \
			"${FUNCNAME[0]}" "$fname" >&2
		return 1
	fi
	# jscpd:ignore-end

	#----- Real Work -----------------------------------------------------
	install-ssh_getUserData "$user" || return 1

	if [ -f "$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d/$lfname" ] ; then
		printf "%s: Error ssh trust %s already exists.\n" \
			"${FUNCNAME[0]}" "$INSTSSH_HOME/.ssh/authorized_keys.d/$lfname" >&2
		return 1
	fi

	install -o "$INSTSSH_UID" -g "$INSTSSH_GID" \
		-d -m 700 "$INSTALL_ROOT$INSTSSH_HOME/.ssh" && \
	install -o "$INSTSSH_UID" -g "$INSTSSH_GID" \
		-d -m 700 "$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d" && \
	true || return 1

	if [ -n "${fname/*:*/}" ] ; then
		cp "$fname" "/tmp/$lfname" || return 1
	else
		scp "$fname" "/tmp/$lfname" || return 1
	fi

	if [ -n "$parms" ] ; then
		parms="$parms " # add trailing blank
	fi
	sed "s:^:$parms:" <"/tmp/$lfname" >"/tmp/$lfname-1"

	install -o "$INSTSSH_UID" -g "$INSTSSH_GID" -m 600 \
		"/tmp/$lfname-1" \
		"$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys.d/$lfname" &&
	rm "/tmp/$lfname" "/tmp/$lfname-1" && \
	true || return 1

	cat "$INSTALL_ROOT$INSTSSH_HOME"/.ssh/authorized_keys.d/* \
		>"$INSTALL_ROOT$INSTSSH_HOME/.ssh/authorized_keys" || \
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

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -n "${fname/*:*/}" ] && [ ! -r "$fname" ] ; then
		printf "%s: Error File %s does not exist or ist not readable.\n" \
			"${FUNCNAME[0]}" "$fname" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	install-ssh_getUserData "$user" || return 1

	install -o "$INSTSSH_UID" -g "$INSTSSH_GID" \
		-d -m 700 "$INSTALL_ROOT$INSTSSH_HOME/.ssh" &&
	if [ -n "${fname/*:*/}" ] ; then
		install -o "$INSTSSH_UID" -g "$INSTSSH_GID" -m 600 "$fname" \
			"$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa" &&
		install -o "$INSTSSH_UID" -g "$INSTSSH_GID" -m 600 "$fname.pub" \
			"$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa.pub" &&
		true || return 1
	else
		scp "$fname" "/tmp/$(basename "$fname")" &&
		scp "$fname.pub" "/tmp/$(basename "$fname").pub" &&
		install -o "$INSTSSH_UID" -g "$INSTSSH_GID" -m 600 "/tmp/$(basename "$fname")" \
			"$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa" &&
		install -o "$INSTSSH_UID" -g "$INSTSSH_GID" -m 600 "/tmp/$(basename "$fname").pub" \
			"$INSTALL_ROOT$INSTSSH_HOME/.ssh/id_rsa.pub" &&
		rm "/tmp/$(basename "$fname")" "/tmp/$(basename "$fname").pub" &&
		true || return 1
	fi

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Key %s for %s completed.\n" "$fname" "$user" >&2

	return 0
}

#### install-ssh_remove-known-host ###########################################
function install-ssh_remove-known-host {
	host="$1"

	# if known_hosts does not exit create it to prevent errors in ssh-keygen
	[ -f ~/.ssh/known_hosts ] || touch ~/.ssh/known_hosts
	ssh-keygen -R "$host"

	return $?
}
