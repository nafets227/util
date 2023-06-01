#!/usr/bin/env bash
#
# (C) 2015 Stefan Schallenberg
#

##### install_mount ##########################################################
function install-mount {
	# Parameters:
	#   1 - Source to mount
	#   2 - Mountpoing [directory]
	#   3 - options

	if [ $# -ne 3 ]; then
		printf "%s: Wrong number of %s parms (should be 3)" \
			"$FUNCNAME" "$#"
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	fgrep " $2 " $INSTALL_ROOT/etc/fstab >/dev/null
	if [ $? -ne 1 ]; then
		echo "Setting up Mount [$1] skipped."
		return 0
	fi

	# Create Source directory if it does not exist
	if [[ "$1" != *":"* ]] && [ ! -e $INSTALL_ROOT/$1 ] ; then
		mkdir -p $INSTALL_ROOT/$1
	fi

	# Create Target directory if it does not exist
	if [ ! -d $INSTALL_ROOT/$2 ]; then
		mkdir -p $INSTALL_ROOT/$2
	fi

	# Create entry in /etc/fstab if it does not exist
	cat >>$INSTALL_ROOT/etc/fstab <<-EOF
		$1 $2 $3
		EOF

	echo "Setting up Mount [$1 $2 $3] completed."

	return 0
}

function install-mount_bind {
	# Parameters:
	#   1 - Source to mount
	#   2 - Mountpoing [directory]
	if [ $# -ne 2 ]; then
		printf "%s: Wrong number of %s parms (should be 2)" \
			"$FUNCNAME" "$#"
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	install-mount "$1" "$2" "none bind 0 0"
}
