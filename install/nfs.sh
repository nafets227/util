#!/usr/bin/env bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### install-nfs_server #####################################################
function install-nfs_server {
	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -f "$INSTALL_ROOT/etc/exports" ] && \
		grep -F "Standard NFS Setup in nafets.de" "$INSTALL_ROOT/etc/exports" >/dev/null ; then
		printf "%s: Error NFS Setup was already done before (see /etc/exports).\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	arch-chroot "$INSTALL_ROOT" \
		pacman -S --needed --noconfirm nfs-utils \
		|| return 1

	if [ ! -d "$INSTALL_ROOT/srv/nfs4" ]; then
		mkdir -p "$INSTALL_ROOT/srv/nfs4" || return 1
	fi

	cat >>"$INSTALL_ROOT/etc/exports" <<-EOF || return 1
		# Standard NFS Setup in nafets.de
		# (C) 2015-2018 Stefan Schallenberg

		EOF

	mv "$INSTALL_ROOT/etc/idmapd.conf" \
		"$INSTALL_ROOT/etc/idmapd.conf.backup" || return 1
	awk -f - "$INSTALL_ROOT/etc/idmapd.conf.backup" \
		>"$INSTALL_ROOT/etc/idmapd.conf" <<-"EOF" || return 1
		BEGIN {global=0}
		/\[Gneral\]/ { global=1; print; next }
		/Domain/ { next }
		/\[/ {
			if (global==1) {
				print "Domain = intranet.nafets.de"
				print ""
				global=2
				}
			}
		{ print }
		EOF

	systemctl --root="$INSTALL_ROOT" enable rpcbind.service nfs-server.service || return 1

	#----- Closing  ------------------------------------------------------
	printf "Setting up NFS Server completed.\n"

	return 0
}

##### install-nfs_export #####################################################
function install-nfs_export {
	# Parameter:
	#     <Dir>        Real Directory to be exported (e.g. /data/myshare)
	#     <Share-Name> Name of the share visibile to clients (e.g. myshare)
	#                  NB: Can contain slashes, but be aware of side-efects
	#     [options]    either ro (default) or rw or a string of options to be
	#                  put as NFS options in /etc/exports
	path="$1"
	exportname="$2"
	options="$3"
	nets="${4:-192.168.108.0/24}"

	#----- Input checks --------------------------------------------------
	if [ $# -lt 2 ]; then
		printf "%s: Internal Error: Got %s Parms (Exp=2+)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ -n "$exportname" ] &&
		grep -F "/srv/nfs4/$exportname" "$INSTALL_ROOT/etc/exports" >&/dev/null ; then
		printf "%s: Error %s already exportet (see /etc/exports)\n" \
			"${FUNCNAME[0]}" "$exportname" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	case $options in
		"" | "ro" )
			exportopt="ro,no_subtree_check,nohide,no_root_squash"
			;;
		"rw" )
			if [ "$exportname" == "" ] ; then
				exportopt="rw,fsid=root,no_subtree_check,crossmnt,no_root_squash"
			else
				exportopt="rw,subtree_check,nohide,no_root_squash"
			fi
			;;
		* )
			exportopt="$3"
	esac

	if [ "$exportname" != "" ] ; then
		install-mount "$path" "/srv/nfs4/$exportname"  "none bind 0 0" || return 1
	fi

	local netopt=""
	for n in $nets ; do
		netopt+=" $n($exportopt)"
	done
	netopt="${netopt:1}" # remove leading blank

	cat >>"$INSTALL_ROOT/etc/exports" <<-EOF
		/srv/nfs4/$exportname $netopt
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Added NFS Export %s from %s (%s)\n" \
		"$exportname" "$path" "$exportopt"

	return 0
}

##### install-nfs_client #####################################################
function install-nfs_client {

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	arch-chroot "$INSTALL_ROOT" \
		pacman -S --needed --noconfirm nfs-utils

	systemctl --root="$INSTALL_ROOT" \
		enable rpcbind.service nfs-client.target remote-fs.target \
	|| return 1

	#----- Closing  ------------------------------------------------------
	printf "Setting up NFS Client completed.\n"

	return 0
}
