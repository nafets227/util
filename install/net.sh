#!/bin/bash
#
# (C) 2015 Stefan Schallenberg
#

##### install_net_br ########################################################
function install-net_br {
	br_name=${1:-br0}

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	cat >$INSTALL_ROOT/etc/systemd/network/nafetsde-$br_name.netdev <<-EOF
		[NetDev]
		Name=$br_name
		Kind=bridge
		EOF

	systemctl --root=$INSTALL_ROOT enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
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
	if [ $# -ne 2 ] ; then
                printf "Internal Error: %s got %s parms (exp=2)\n" \
                        "$FUNCNAME" "$#" >&2
                return 1
        elif [ ! -d "$INSTALL_ROOT" ] ; then
                printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
                        "$FUNCNAME" "$INSTALL_ROOT" >&2
                return 1
        fi

	#----- Real Work -----------------------------------------------------
	if [ -z $virt ] ; then
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	cat >$cfgfile <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=macvlan

		[MACVLAN]
		Mode=bridge
		EOF

	if [ ! -z $virt ] ; then
	    cat >>$cfgfile <<-EOF
		[Match]
		Virtualization=$virt
		EOF
	fi

	systemctl --root=$INSTALL_ROOT enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
	printf "Setup of macvlan %s " "$vlan_name" >&2
	if [ ! -z $virt ] ; then
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
	if [ $# -ne 2 ] ; then
                printf "Internal Error: %s got %s parms (exp=2)\n" \
                        "$FUNCNAME" "$#" >&2
                return 1
        elif [ ! -d "$INSTALL_ROOT" ] ; then
                printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
                        "$FUNCNAME" "$INSTALL_ROOT" >&2
                return 1
        fi

	#----- Real Work -----------------------------------------------------
	if [ -z $virt ] ; then
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	cat >$cfgfile <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=ipvlan

		[IPVLAN]
		Mode=L2
		Flags=bridge
		EOF

	if [ ! -z $virt ] ; then
	    cat >>$cfgfile <<-EOF
		[Match]
		Virtualization=$virt
		EOF
	fi

	systemctl --root=$INSTALL_ROOT enable systemd-networkd.service

	#----- Closing  ------------------------------------------------------
	printf "Setup of ipvlan %s " "$vlan_name" >&2
	if [ ! -z $virt ] ; then
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
                        "$FUNCNAME" "$#" >&2
                return 1
        elif [ ! -d "$INSTALL_ROOT" ] ; then
                printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
                        "$FUNCNAME" "$INSTALL_ROOT" >&2
                return 1
        fi

	#----- Real Work -----------------------------------------------------
	if [ -z $virt ] ; then
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	else
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name-$virt.netdev"
	fi
	cat >$cfgfile <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=vlan

		[VLAN]
		Id=$vlan_id
		EOF

	if [ ! -z $virt ] ; then
	    cat >>$cfgfile <<-EOF
		[Match]
		Virtualization=$virt
		EOF
	fi
	#----- Closing  ------------------------------------------------------
	printf "Setting up vlan %s with ID %s " \
		"$vlan_name" "$vlan_id"
	if [ ! -z $virt ] ; then
		printf "[Virt=%s] " "$virt"
	fi
	printf "completed.\n"

	return 0
}
##### install_net_static ( ipaddr, [ifache="eth0"], [virt=""] ################
function install-net_static {
	local ipaddr="$1"
	local iface="$2"
	local virt="${3:-""}"
	local vlan="${4:-""}"
	local macvlan="${5:-""}"
	local ipvlan="${6:-""}"
	local bridge="${7:-""}"
	local forward="${8:-""}"

	#----- Input checks --------------------------------------------------
	if [ $# -lt 2 ]; then
		printf "Internal Error: %s got %s parms (exp=2++)\n" \
                        "$FUNCNAME" "$#" >&2
		return 1
        elif [ ! -d "$INSTALL_ROOT" ] ; then
                printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
                        "$FUNCNAME" "$INSTALL_ROOT" >&2
                return 1
        fi

	#----- Real Work -----------------------------------------------------
	if [ -z $virt ] ; then
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$iface.network"
	else
		local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$iface-$virt.network"
	fi

	cat >$cfgfile <<-EOF
		[Match]
		Name=$iface
		EOF

	if [ ! -z $virt ] ; then
	    cat >>$cfgfile <<-EOF
		Virtualization=$virt
		EOF
	fi

	cat >>$cfgfile <<-EOF

		[Network]
		Description="Static IP Adress in nafets.de"
		DHCP=no
		EOF
	if [ ! -z "$ipaddr" ] ; then
		for f in $ipaddr ; do
			if [[ $f != */* ]] ; then
				f+="/24"
			fi
			echo "Address=$f" >>$cfgfile
		done
		local primary_ip=${ipaddr%% *}
		local ip_net=${primary_ip%.*}
		local dom="dom.nafets.de intranet.nafets.de"
		# @TODO: Find a better way to detect if we have a test machine
		if [ ! -z $virt ] && [ $virt == "yes" ] ; then
			local dom="test.nafets.de $dom"
		fi
		# @TODO: Find a better way to detect the main Interface
		if [ "$ip_net" == "192.168.108" ] ; then
			cat >>$cfgfile <<-EOF
				Gateway=$ip_net.250
				DNS=$ip_net.1
				DNS=$ip_net.250
				NTP=$ip_net.1
				Domains=$dom
				EOF
		fi
	else
		cat <<-EOF >>$cfgfile || return 1
			IPv6AcceptRouterAdvertisements=false
			LLMNR=no
			LinkLocalAddressing=no
			IPv6AcceptRA=no
			EOF
	fi
	
	if [ ! -z "$vlan" ] ; then for f in $vlan ; do
		cat >>$cfgfile <<-EOF
			VLAN=$f
			EOF
	done; fi

	if [ ! -z "$macvlan" ] ; then for f in $macvlan ; do
		cat >>$cfgfile <<-EOF
			MACVLAN=$f
			EOF
	done; fi

	if [ ! -z $ipvlan ] ; then for f in $ipvlan ; do
		cat >>$cfgfile <<-EOF
			IPVLAN=$f
		EOF
	done; fi

	if [ ! -z $bridge ] ; then for f in $bridge ; do
		cat >>$cfgfile <<-EOF
			Bridge=$f
		EOF
	done; fi

	if [ ! -z "$forward" ] ; then 
		cat >>$cfgfile <<-EOF
			IPForward=$forward
		EOF
	fi


	if [ -f $INSTALL_ROOT/etc/resolv.conf ] || [ -l $INSTALL_ROOT/etc/resolv.conf ]; then
	    rm $INSTALL_ROOT/etc/resolv.conf
	fi
	ln -s /run/systemd/resolve/resolv.conf $INSTALL_ROOT/etc/resolv.conf

	systemctl --root=$INSTALL_ROOT enable \
		systemd-networkd.service \
		systemd-resolved.service \
		systemd-timesyncd.service
	local ntp_info

	#----- Closing  ------------------------------------------------------
	printf "Setting up network [Static %s on %s] completed.\n" \
		"${ipaddr:="<noIP>"}" "$iface"
	if [ ! -z "$virt" ] ; then
		printf "\tVirt=%s\n" "$virt"
	fi
	if [ ! -z "$vlan" ] ; then
		printf "\tVLANs=%s\n" "$vlan"
	fi
	if [ ! -z "$macvlan" ] ; then
		printf "\tMACVLANs=%s\n" "$macvlan"
	fi
	if [ ! -z "$ipvlan" ] ; then
		printf "\tIPVLANs=%s\n" "$ipvlan"
	fi
	if [ ! -z "$bridge" ] ; then
		printf "\tBridges=%s\n" "$bridge"
	fi

	return 0
}

##### install_net_dhcp #######################################################
# Install a secondary network interface that is somehow restricted
# Parameter:
#      iface               - name of interface, wildcards allowed
#      hostname [optional] - hostname to use to get address via DHCP 
#      virt                - restrict to virtualisation [yes/no], both if empty
function install-net_dhcp {
	local iface=${1:-""}
	local hostname=${2:-""}
	local virt=${3:-""}

	if [ -z $virt ] ; then
		local readonly cfgfilename="nafetsde-$iface.network"
	else
		local readonly cfgfilename="nafetsde-$iface-$virt.network"
	fi
	local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/$cfgfilename"

	if [ ! -z "$iface" ] ; then
		cat >$cfgfile <<-EOF
			[Match]
			Name=$iface
		EOF
	fi

	if [ ! -z $virt ] ; then
		cat >>$cfgfile <<-EOF
			Virtualization=$virt
		EOF
	fi

	cat >>$cfgfile <<-EOF

		[Network]
		Description="Secondary Interface with DHCP in nafets.de"
		DHCP=ipv4
	EOF

	if [ ! -z $hostname ]; then
		cat >>$cfgfile <<-EOF

			[DHCP]
			Hostname=$hostname
		EOF
	fi

	systemctl --root=$INSTALL_ROOT enable \
		systemd-networkd.service \
		systemd-resolved.service \
		systemd-timesyncd.service \
		|| return 1
	# systemctl --root=$INSTALL_ROOT enable \
	#	systemd-networkd-wait-online.service

	printf "Setting up Network %s [dhcp" "$iface"
	if [ ! -z $hostname ] ; then
	    printf ", hostname=%s" "$hostname"
	fi
	if [ ! -z $virt ] ; then
	    printf ", virtualisation=%s" "$virt"
	fi
	printf "] completed.\n"
}

