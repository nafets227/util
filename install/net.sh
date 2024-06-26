#!/usr/bin/env bash
#
# (C) 2015 Stefan Schallenberg
#

##### install_net_br ########################################################
function install-net_br {
	br_name=${1:-br0}

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	cat >"$INSTALL_ROOT/etc/systemd/network/nafetsde-$br_name.netdev" <<-EOF
		[NetDev]
		Name=$br_name
		Kind=bridge
		EOF

	systemctl --root="$INSTALL_ROOT" enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
	#shellcheck disable=SC2181
	if [ $? -eq 0 ] ; then
		printf "Setup of bridge %s completed\n" "$br_name" >&2
		return 0
	else
		printf "ERROR setting up bridge %s\n" "$br_name" >&2
		return 1
	fi
}

##### install_net_macvlan ####################################################
function install-net_macvlan {
	vlan_name=${1:-macvlan0}
	virt="$2"

	#----- Input checks --------------------------------------------------
	# jscpd:ignore-start
	if [ $# -ne 2 ] ; then
		printf "Internal Error: %s got %s parms (exp=2)\n" \
			"${FUNCNAME[0]}" "$#" >&2
			return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	if [ -z "$virt" ] ; then
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	# jscpd:ignore-end
	cat >"$cfgfile" <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=macvlan

		[MACVLAN]
		Mode=bridge
		EOF

	if [ -n "$virt" ] ; then
		cat >>"$cfgfile" <<-EOF
			[Match]
			Virtualization=$virt
			EOF
	fi

	systemctl --root="$INSTALL_ROOT" enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
	printf "Setup of macvlan %s " "$vlan_name" >&2
	if [ -n "$virt" ] ; then
		printf "[Virt=%s] " "$virt"
	fi
	printf "completed.\n"

	return 0
}

##### install_net_vlan #######################################################
function install-net_ipvlan {
	vlan_name=${1:-ipvlan0}
	virt="$2"

	#----- Input checks --------------------------------------------------
	# jscpd:ignore-start
	if [ $# -ne 2 ] ; then
		printf "Internal Error: %s got %s parms (exp=2)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	if [ -z "$virt" ] ; then
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	# jscpd:ignore-end
	cat >"$cfgfile" <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=ipvlan

		[IPVLAN]
		Mode=L2
		Flags=bridge
		EOF

	if [ -n "$virt" ] ; then
		cat >>"$cfgfile" <<-EOF
			[Match]
			Virtualization=$virt
			EOF
	fi

	systemctl --root="$INSTALL_ROOT" enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
	printf "Setup of ipvlan %s " "$vlan_name" >&2
	if [ -n "$virt" ] ; then
		printf "[Virt=%s] " "$virt"
	fi
	printf "completed.\n"

	return 0
}

##### install_net_vlan #######################################################
function install-net_vlan {
	vlan_name="$1"
	vlan_id="$2"
	virt="$3"

	#----- Input checks --------------------------------------------------
	if [ $# -lt 2 ] ; then
		printf "Internal Error: %s got %s parms (exp=2+)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	if [ -z "$virt" ] ; then
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	cat >"$cfgfile" <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=vlan

		[VLAN]
		Id=$vlan_id
		EOF

	if [ -n "$virt" ] ; then
		cat >>"$cfgfile" <<-EOF
			[Match]
			Virtualization=$virt
			EOF
	fi
	#----- Closing  ------------------------------------------------------
	printf "Setting up vlan %s with ID %s " \
		"$vlan_name" "$vlan_id"
	if [ -n "$virt" ] ; then
		printf "[Virt=%s] " "$virt"
	fi
	printf "completed.\n"

	return 0
}

##### install_net_static3 ( ipaddr, tagname, match-condition #################
function install-net_static3 {
	local ipaddr=$1
	local tag=$2
	local match=$3
	local addparms
	addparms=$(cat /dev/stdin) || return 1 # cat stdin for optional parms

	#----- Input checks --------------------------------------------------
	if [ $# -ne 3 ]; then
		printf "Internal Error: %s got %s parms (exp=3)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/$tag.network"

	cat >"$cfgfile" <<-EOF
		[Match]
		$match
		EOF

	# enable Multicast on all interfaces that are configured with an
	# IP adress (e.g. NOT vlan's etc.)
	if [ -n "$ipaddr" ] ; then
		cat >>"$cfgfile" <<-EOF
			[Link]
			Multicast=true
			EOF
	else
		cat >>"$cfgfile" <<-EOF
			[Link]
			Multicast=false
			EOF
	fi

	cat >>"$cfgfile" <<-EOF
		[Network]
		Description="Static IP Adress in nafets.de"
		DHCP=no
		EOF
	if [ -n "$ipaddr" ] ; then
		for f in $ipaddr ; do
			if [[ $f != */* ]] ; then
				f+="/24"
			fi
			echo "Address=$f" >>"$cfgfile"
		done
	else
		cat <<-EOF >>"$cfgfile" || return 1
			IPv6AcceptRouterAdvertisements=false
			LLMNR=no
			LinkLocalAddressing=no
			IPv6AcceptRA=no
			EOF
	fi

	cat <<-EOF >>"$cfgfile" || return 1
		$addparms
		EOF

	if [ -f "$INSTALL_ROOT/etc/resolv.conf" ] || [ -L "$INSTALL_ROOT/etc/resolv.conf" ] ; then
		rm "$INSTALL_ROOT/etc/resolv.conf"
	fi
	ln -s /run/systemd/resolve/resolv.conf "$INSTALL_ROOT/etc/resolv.conf"

	systemctl --root="$INSTALL_ROOT" enable \
		systemd-networkd.service \
		systemd-resolved.service \
		systemd-timesyncd.service

	#----- Closing  ------------------------------------------------------
	printf "Setting up network [Static %s] completed. Match:\n%s\n" \
		"${ipaddr:-"<noIP>"}" "$match"
	if [ -n "$addparms" ] ; then
		printf "\t%s\n" "$addparms"
	fi

	return 0
}
##### DEPRECATED install_net_static2 ( ipaddr, [ifache="eth0"], [virt=""] ###############
function install-net_static2 {
	# DEPRECATED, use install_net_static3 instead
	local ipaddr="$1"
	local iface="$2"
	local virt="${3:-""}"

	#----- Input checks --------------------------------------------------
	if [ $# -lt 2 ]; then
		printf "Internal Error: %s got %s parms (exp=2++)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	iface_fname=${iface//\*/_}
	iface_fname=${iface_fname// /_}

	if [ -z "$virt" ] ; then
		local -r iftag="$iface_fname"
	else
		local -r iftag="$iface_fname-$virt"
	fi

	ifmatch="Name=$iface"
	if [ -n "$virt" ] ; then
		ifmatch+=$'\n'"Virtualization=$virt"
	fi

	install-net_static3 "$ipaddr" "50-nafetsde-$iftag" "$ifmatch" || return 1

	return 0
}
##### DEPRECATED install_net_static ( ipaddr, [ifache="eth0"], [virt=""] #####
function install-net_static {
	# DEPRECATED, use install_net_static3 instead
	local ipaddr="$1"
	local iface="$2"
	local virt="${3:-""}"
	local vlan="${4:-""}"
	local macvlan="${5:-""}"
	local ipvlan="${6:-""}"
	local bridge="${7:-""}"
	local forward="${8:-""}"
	local ip6token="${9:-""}"

	#----- Input checks --------------------------------------------------
	if [ $# -lt 2 ]; then
		printf "Internal Error: %s got %s parms (exp=2++)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	fi
	# $INSTALL_ROOT to be checked by install-net_static2

	#----- Real Work -----------------------------------------------------
	local ipparm=""
	if [ -n "$ipaddr" ] ; then
		local primary_ip=${ipaddr%% *}
		local ip_net=${primary_ip%.*}
		local dom="dom.nafets.de intranet.nafets.de"
		# @TODO: Find a better way to detect if we have a test machine
		if [ -n "$virt" ] && [ "$virt" == "yes" ] ; then
			local dom="test.nafets.de $dom"
		fi
		# @TODO: Find a better way to detect the main Interface
		if [ "$ip_net" == "192.168.108" ] ; then
			ipparm=$(cat <<-EOF
				Gateway=$ip_net.250
				DNS=$ip_net.10
				DNS=$ip_net.250
				NTP=$ip_net.250
				Domains=$dom
				EOF
			)
		fi
	fi

	if [ -n "$vlan" ] ; then for f in $vlan ; do
		ipparm+="VLAN=$f"$'\n'
	done; fi

	if [ -n "$macvlan" ] ; then for f in $macvlan ; do
		ipparm+="MACVLAN=$f"$'\n'
	done; fi

	if [ -n "$ipvlan" ] ; then for f in $ipvlan ; do
		ipparm+="IPVLAN=$f"$'\n'
	done; fi

	if [ -n "$bridge" ] ; then for f in $bridge ; do
		ipparm+="Bridge=$f"$'\n'
	done; fi

	if [ -n "$forward" ] ; then
		ipparm+="IPForward=$forward"$'\n'
	fi

	if [ -n "$ip6token" ] ; then
		ipparm+="IPv6Token=$ip6token"$'\n'
	fi

	install-net_static2 "$ipaddr" "$iface" "$virt" <<-EOF
		$ipparm
		EOF

	return $?
}

##### install_net_dhcp #######################################################
function install-net_dhcp {
	# Install a secondary network interface that is somehow restricted
	# Parameter:
	#      iface               - name of interface, wildcards allowed
	#      hostname [optional] - hostname to use to get address via DHCP
	#      virt                - restrict to virtualisation [yes/no], both if empty
	local iface=${1:-""}
	local hostname=${2:-""}
	local virt=${3:-""}

	iface_fname=${iface//\*/_}
	iface_fname=${iface_fname// /_}

	if [ -z "$virt" ] ; then
		local -r cfgfilename="nafetsde-$iface_fname.network"
	else
		local -r cfgfilename="nafetsde-$iface_fname-$virt.network"
	fi
	local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/$cfgfilename"

	if [ -n "$iface" ] ; then
		cat >"$cfgfile" <<-EOF
			[Match]
			Name=$iface
		EOF
	fi

	if [ -n "$virt" ] ; then
		cat >>"$cfgfile" <<-EOF
			Virtualization=$virt
		EOF
	fi

	cat >>"$cfgfile" <<-EOF

		[Network]
		Description="Secondary Interface with DHCP in nafets.de"
		DHCP=ipv4
	EOF

	if [ -n "$hostname" ]; then
		cat >>"$cfgfile" <<-EOF

			[DHCP]
			Hostname=$hostname
		EOF
	fi

	systemctl --root="$INSTALL_ROOT" enable \
		systemd-networkd.service \
		systemd-resolved.service \
		systemd-timesyncd.service \
		|| return 1
	# systemctl --root="$INSTALL_ROOT" enable \
	#	systemd-networkd-wait-online.service

	printf "Setting up Network %s [dhcp" "$iface"
	if [ -n "$hostname" ] ; then
		printf ", hostname=%s" "$hostname"
	fi
	if [ -n "$virt" ] ; then
		printf ", virtualisation=%s" "$virt"
	fi
	printf "] completed.\n"
}

##### install-net_wlan #######################################################
function install-net_wlan {
	# Install a WLAN adapter
	# Parameter:
	#      iface  - name of interface, wildcards allowed
	#      SSID   - SSID of the WLAN to be connected to
	#      wlanpw - WLAN Password
	local iface="$1"
	local ssid="$2"
	local wlanpw="$3"

	#----- Input checks --------------------------------------------------
	if [ $# -ne 3 ]; then
		printf "Internal Error: %s got %s parms (exp=3)\n" \
			"${FUNCNAME[0]}" "$#" >&2
		return 1
	elif [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	iface_fname=${iface//\*/_}
	iface_fname=${iface_fname// /_}

	local -r cfgfilename="nafetsde-$iface_fname.network"
	local -r cfgfile="$INSTALL_ROOT/etc/systemd/network/$cfgfilename"

	pacman -S --sysroot "$INSTALL_ROOT" --needed --noconfirm wpa_supplicant &&

	cat >"$cfgfile" <<-EOF &&
		[Match]
		Name=$iface

		[Network]
		Description="WLAN Interface with DHCP in nafets.de"
		DHCP=yes
		IPv6PrivacyExtensions=true

		[DHCPv4]
		RouteMetric=2048
	EOF

	local -r cfgdirwpa="$INSTALL_ROOT/etc/wpa_supplicant" &&
	local -r cfgfilewpa="$cfgdirwpa/wpa_supplicant-$iface_fname.conf" &&
	cat >"$cfgfilewpa" <<-EOF &&
		ctrl_interface=/var/run/wpa_supplicant
		ctrl_interface_group=wheel
		update_config=1
		eapol_version=1
		ap_scan=1
		fast_reauth=1
		EOF
	wpa_passphrase "$ssid" <<<"$wlanpw" >>"$cfgfilewpa" &&

	systemctl --root="$INSTALL_ROOT" enable \
		systemd-networkd.service \
		wpa_supplicant@"$iface_fname" \
		systemd-resolved.service \
		systemd-timesyncd.service \
		&& \
	true || return 1

	printf "Setting up WLAN Network %s completed.\n" "$iface"

	return 0
}
