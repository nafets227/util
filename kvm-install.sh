#!/bin/bash
#
# kvm-install
#
# Install virtaul machine in KVM
#
# (C) 2017 Stefan Schallenberg

##### parseParm - parse Parameters and set global variables ##################
function parseParm () {
	local readonly def_memory="1024M"
	
	if [ "$#" -lt 1 ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	vmname="$1"
	shift
	
	while [ $# -gt 0 ] ; do
		parm="${1%%=*}"
		if [ "$1" != "$parm" ] ; then # contains =
			value=${1#*=}
		else
			value="$2"
			shift
		fi
		shift
		
		#DEBUG printf "DEBUG: parm %s value \"%s\"\n" "$parm" "$value" >&2
		case "$parm" in
			--boot | --root | --dev* )
				prm_dev="$value"
				;;
			--mem )
				prm_mem="$value"
				;;
			*)
				printf "Error: unknown Parameter %s with value %s\n" \
					"$parm" "$value"
				return 1				
		esac
	done

	return 0
}

##### getDefaultBootDevice ###################################################
# Parameter:
#   1 - virtual machine name
function getDefaultBootDevice () {
	vmname="$1"
	if [ -b /dev/vg-sys/$vmname ] ; then
		printf "/dev/vg-sys/%s\n" "$vmname"
	elif [ -e /var/lib/libvirt/images/$vmname.raw ] ; then
		printf "/var/lib/libvirt/images/%s.raw\n" "$vmname"
	else
		printf "No Default Device found for machine %s. Candidates:\n" "$vmname" >&2
		printf "\t/dev/vg-sys/%s\n" "$vmname" >&2
		printf "\t/var/lib/libvirt/images/%s.raw\n" "$vmname" >&2
		return 1		
	fi		
} 

##### getNetworkDevice #######################################################
# choose Network Device
# we use the first non-loopback device of "IP link show"
function getNetworkDevice () {
	ifaces="$(ip link show | sed -n -e 's/\([0-9]\+: \)\([^:]\+\).*/\2/p')"
	rc=$? ; if [ "$rc" -ne 0 ] ; then return $rc; fi
	
	for if in $ifaces ; do
		if [ "$if" == "lo" ] ; then #ignore loopback device
			/bin/true
		else
			printf "%s\n" $if
			return 0
		fi
	done 
	}

##### Main ###################################################################
# Parameters:
# 1 - machinename [mandatory]
# Options:
#   --dev <device> [optional, autodetected]
#   --mem <size> [default=1024MB]
#

# Set Default values
prm_mem="1024K"
netdev=$(getNetworkDevice)
rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi

# Parse Parameters
parseParm "$@"
rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi

# Find Device if not given on commandline
if [ -z "$prm_dev" ] ; then
	prm_dev=$(getDefaultBootDevice $vmname)
	rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi
fi

# Tell user what we do
printf "%s: Installing machine %s\n" "$(basename $BASH_SOURCE .sh)" "$vmname"
printf "\tmemory %s\n" "$prm_mem"
printf "\tdevice %s\n" "$prm_dev"
printf "\tnetwork %s\n" "$netdev"

# Action !
echo virt-install --name "$1" --memory 768 --import \
	--disk $prm_boot,format=raw \
	--network type=direct,source=$netdev:mactap \
	--memory=$prm_mem

