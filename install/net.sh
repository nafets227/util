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

##### install_net_vlan #######################################################
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
	local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
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
function install-net_vlan {
	vlan_name="$1"
	vlan_id="$2"

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
	local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-$vlan_name.netdev"
	cat >$cfgfile <<-EOF
		[NetDev]
		Name=$vlan_name
		Kind=vlan

		[VLAN]
		Id=$vlan_id
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Setting up vlan %s with ID %s completed.\n" \
		"$vlan_name" "$vlan_id"

	return 0
}
##### install_net_static ( ipaddr, [ifache="eth0"], [virt=""] ################
function install-net_static {
	local ipaddr="$1"
	local iface=${2:-eth0}
	local virt=${3:-""}
	local vlan=${4:-""}
	
	#----- Input checks --------------------------------------------------
	if [ $# -lt 1 ]; then
		printf "Internal Error: %s got %s parms (exp=1++)\n" \
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
		DHCP=none
		EOF
	for f in $ipaddr ; do
		echo "Address=$f/24" >>$cfgfile
	done
	local primary_ip=${ipaddr%% *}
	local ip_net=${primary_ip%.*}
	cat >>$cfgfile <<-EOF
		Gateway=$ip_net.250
		DNS=$ip_net.1
		DNS=$ip_net.250
		NTP=$ip_net.1
		EOF
	
	if [ ! -z "$vlan" ] ; then for f in $vlan ; do
		echo "VLAN=$f" >>$cfgfile
	done; fi

	if [ ! -z $virt ] && [ $virt == "yes" ] ; then
		cat >>$cfgfile <<-EOF
			Domains=test.nafets.de dom.nafets.de intranet.nafets.de
			EOF
	else
		cat >>$cfgfile <<-EOF
			Domains=dom.nafets.de intranet.nafets.de
			EOF
	fi

	if [ -f $INSTALL_ROOT/etc/resolv.conf ] || [ -l $INSTALL_ROOT/etc/resolv.conf ]; then
	    rm $INSTALL_ROOT/etc/resolv.conf
	fi
	ln -s /run/systemd/resolve/resolv.conf $INSTALL_ROOT/etc/resolv.conf

	systemctl --root=$INSTALL_ROOT enable systemd-networkd.service systemd-resolved.service
	local ntp_info

	#----- Closing  ------------------------------------------------------
	printf "Setting up network [Static %s on %s" \
		"$ipaddr" "$iface"
	if [ ! -z $virt ] ; then
		printf " Virt=%s" "$virt"
	fi
	if [ ! -z $vlan ] ; then
		printf " VLANs=%s" "$vlan"
	fi
	printf "] completed.\n"

	return 0
}

##### install_net_switch ( [ifache="eth0"] ) #################################
function install-net_switch {
	iface=${1:-eth0}
	bridge=$2
	macvlan="$3"

	#----- Input checks --------------------------------------------------
	if [ $# -ne 3 ] ; then
                printf "Internal Error: %s got %s parms (exp=3)\n" \
                        "$FUNCNAME" "$#" >&2
                return 1
        elif [ ! -d "$INSTALL_ROOT" ] ; then
                printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
                        "$FUNCNAME" "$INSTALL_ROOT" >&2
                return 1
	elif [ -z "$bridge" ] && [ -r "$macvlan" ] ; then
		printf "%s: " "$FUNCNAME" >&2
		printf "Either bridge (\$2) or macvlan (\$3) must be given\n" \
			>&2
                return 1
        fi

	#----- Real Work -----------------------------------------------------
	local readonly cfgfile="$INSTALL_ROOT/etc/systemd/network/nafetsde-switch.network"
	cat >$cfgfile <<-EOF
		[Match]
		Name=$iface

		[Network]
		Description="Set Link up for openvswitch, no IP Adress"
		DHCP=none
		EOF
	if [ ! -z $bridge ] ; then
		cat >>$cfgfile <<-EOF
			[Network]
			Bridge=$bridge
		EOF
	elif [ ! -z "$macvlan" ] ; then
		cat >>$cfgfile <<-EOF
			[Network]
		EOF
		for f in $macvlan ; do
			cat >>$cfgfile <<-EOF
				MACVLAN=$f
			EOF
		done
	fi

	systemctl --root=$INSTALL_ROOT enable systemd-networkd.service 

	#----- Closing  ------------------------------------------------------
	printf "Setting up Network [Switch-Device %s] completed.\n" \
		"$iface"

	return 0
}

##### install_net_dhcp ######################################################
#function install-net_dhcp {
#cat >/etc/systemd/network/nafetsde-dhcp.network <<EOF
#[Match]
#Name=eth* en*
#
#[Network]
#DHCP=both
#EOF
#
#mkdir -p /etc/systemd/system/systemd-timesyncd.service.d
#echo -e "[Unit]\nConditionVirtualization=" > /etc/systemd/system/systemd-timesyncd.service.d/allow_virt.conf
#systemctl daemon-reload
#
#systemctl enable \
#    systemd-networkd.service \
#    systemd-resolved.service \
#    systemd-timesyncd.service
#    
#systemctl reload-or-restart \
#    systemd-networkd.service \
#    systemd-resolved.service \
#    systemd-timesyncd.service
#
##BUGFIX: resolved is not correctly creating resolve.conf
## from DHCP for searchlist and DNS Server
## see https://bugs.freedesktop.org/show_bug.cgi?id=85397
#systemctl disable systemd-resolved
#systemctl stop systemd-resolved
#cat >/etc/resolv.conf <<-EOF
#	nameserver 192.168.108.1 192.168.108.250
#	search dom.nafets.de intranet.nafets.de
#	EOF
#
#systemctl enable systemd-networkd-wait-online.service
#/usr/lib/systemd/systemd-networkd-wait-online
#
#echo "Setting up Network [dhcp] completed."
#}

##### install_net_dhcp2 #####################################################
# Install a secondary network interface that is somehow restricted
# Parameter:
#      iface               - name of interface, wildcards allowed
#      hostname [optional] - hostname to use to get address via DHCP 
#function install-net_dhcp2 {
#if [ $# -lt 1 ] ; then
#    echo "$0 install_net_static ERROR: Wrong number of parameters ($# instead of 1 or 2)."
#    return -1
#fi
#
#local iface=$1
#local hostname=${2:-""}
#local virt=${3:-""}
#
#if [ -z $virt ] ; then
#    local readonly cfgfile="/etc/systemd/network/nafetsde-$iface.network"
#else
#    local readonly cfgfile="/etc/systemd/network/nafetsde-$iface-$virt.network"
#fi
#
#cat >$cfgfile <<-EOF
#	[Match]
#	Name=$iface
#	EOF
#
#if [ ! -z $virt ] ; then
#    cat >>$cfgfile <<-EOF
#	Virtualization=$virt
#	EOF
#fi
#
#cat >>$cfgfile <<-EOF
#
#	[Network]
#	Description="Secondary Interface with DHCP in nafets.de"
#	DHCP=both
#	EOF
#
#if [ ! -z $hostname ]; then	
#    cat >>$cfgfile <<-EOF
#
#	[DHCP]
#	Hostname=$hostname
#	EOF
#fi
#
#systemctl reload-or-restart systemd-networkd.service
#
#printf "Setting up secondarys Network %s [dhcp" "$iface"
#if [ ! -z $hostname ] ; then
#    printf ", hostname=%s" "$hostname"
#fi
#if [ ! -z $virt ] ; then
#    printf ", virtualisation=%s" "$virt"
#fi
#printf "]\n"
#}

