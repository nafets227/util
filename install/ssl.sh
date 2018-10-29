#!/bin/bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### Configuration ##########################################################
readonly INSTALL_SSL_SOURCE="/data/ca/private /etc/ca-certificates/extracted/cadir"

##### install-ssh_trust ######################################################
function install-ssl_nafetsca {
	
 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi
 	
	#----- Real Work -----------------------------------------------------

	for dir in $INSTALL_SSL_SOURCE ; do
		if [ -f "$dir/nafetsde-ca.crt" ] ; then
			casrc="$dir/nafetsde-ca.crt"
		elif [ -f "$dir/nafets.de_CA.pem" ] ; then
			casrc="$dir/nafets.de_CA.pem"
		fi
		if [ ! -z "$casrc" ] ; then
			break;
		fi
	done

	if [ -z "$casrc" ] ; then
		printf "Nafets CA public cert not found as "
		printf "nafetsde-ca.crt or nafets.de_CA.pem\n"
		printf " in one of %s\n" "$INSTALL_SSL_SOURCE"
		return 1
	fi

	install -o 0 -g 0 -m 644 \
		$casrc \
		$INSTALL_ROOT/etc/ca-certificates/trust-source/anchors/nafetsde-ca.pem \
		|| return 1
	arch-chroot $INSTALL_ROOT <<-EOF
		update-ca-trust extract
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Trusted SSL CA nafets.de\n"

	return 0
}	
