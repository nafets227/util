#!/bin/bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### Configuration ##########################################################
readonly INSTALL_SSL_SOURCE="/data/ca/private"

##### install-ssh_trust ######################################################
function install-ssl_nafetsca {
	
 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi
 	
	#----- Real Work -----------------------------------------------------

	install -o 0 -g 0 -m 644 \
		$INSTALL_SSL_SOURCE/nafetsde-ca.crt \
		$INSTALL_ROOT/etc/ca-certificates/trust-source/anchors/nafetsde-ca.pem \
		|| return 1
	arch-chroot $INSTALL_ROOT <<-EOF
		update-ca-trust extract
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Trusted SSL CA nafets.de\n"

	return 0
}	
