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
			value_present=1
		else
			value_present=0
		fi
		shift
		
		#DEBUG printf "DEBUG: parm %s value \"%s\"\n" "$parm" "$value" >&2
		case "$parm" in
			--boot | --root | --dev* )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_dev="$value"
				;;
			--mem )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_mem="$value"
				;;
			--cpu )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_cpu="$value"
				;;
			--id )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_id="$value"
				;;
			--virt )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_virt="$value"
				;;
			--replace )
				prm_replace="${value:-1}"
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
	
	for ifc in $ifaces ; do
		if [ "$ifc" == "lo" ] ; then #ignore loopback device
			/bin/true
		else
			printf "%s\n" $ifc
			return 0
		fi
	done 
	}

##### getDefaultID ###########################################################
# return a unique 8bit ID to be used in various places like MAC adr, VNC port
# Parameters:
# 1 - machinename [mandatory]
function getDefaultID() {
	if [ "$#" -lt 1 ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	vmname="$1"
	
	case $vmname in
		xen1 | vXen1 | kvm1 | vKvm1 )
			id="21" ;;
		xen2 | vXen2 | kvm2 | vKvm2 )
			id="22" ;;
		vDom   ) id="06" ;;
		vVdr   ) id="01" ;;
		vSrv   ) id="05" ;;
		vMgmt  ) id="03" ;;
		vWin   ) id="12" ;;
		
		vKube1 ) id="31" ;;
		vKube2 ) id="32" ;;
		vKube3 ) id="33" ;;
		
		vTest  ) id="08" ;;
		vVdrNew) id="21" ;;
	esac

	if [ -z "$id" ] ; then
		return 1
	else
		printf "%s\n" "$id"
		return 0
	fi
	}

##### Main ###################################################################
# Parameters:
# 1 - machinename [mandatory]
# Options:
#   --dev <device> [optional, autodetected]
#   --mem <size> [default=1024MB]
#   --cpu <nr of config> [default: 3,cpuset=2-3]
#         CPU #0 is intended for physical machine only
#         CPU #1 is intende vor Vdr only
#   --id   internal ID, needs to be unique in whole system
#         [default: use a static mapping table inside this script]
#   --replace replace existing VMs [default=no]

# Set Default values
prm_mem="768"
prm_cpu="3,cpuset=2-3"
prm_replace="0"
prm_virt="kvm"
netdev=$(getNetworkDevice)
rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi

# Parse Parameters
parseParm "$@"
rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi

# Calculate Domain ID to be used as unique number where needed
# e.g. in MAC adress
if [ -z "$prm_id" ] ; then
	prm_id=$(getDefaultID $vmname)
	rc=$?; if [ "$rc" -ne 0 ] ; then
		printf "No ID given (--id) and no Default found for machine %s.\n" \
			"$vmname" >&2
		exit $rc;
	fi
fi

# Find Device if not given on commandline
if [ -z "$prm_dev" ] ; then
	prm_dev=$(getDefaultBootDevice $vmname)
	rc=$?; if [ "$rc" -ne 0 ] ; then exit $rc; fi
fi


# Tell user what we do
printf "%s: Installing machine %s (ID=%s)\n" \
	"$(basename $BASH_SOURCE .sh)" \
	"$vmname" \
	"$prm_id"
printf "\tmemory %s\n" "$prm_mem"
printf "\tcpu %s\n" "$prm_cpu"
printf "\tdevice %s\n" "$prm_dev"
printf "\tnetwork %s\n" "$netdev"
printf "\tVirtualisation: %s\n" "$prm_virt"

# Action !
virt_prms="
	--name "$1"
	--virt-type $prm_virt
	--memory "$prm_mem"
	--vcpus "$prm_cpu"
	--cpu host
	--import
	--disk $prm_dev,format=raw,bus=virtio
	--network type=direct,source=$netdev,source_mode=bridge,model=virtio,mac=00:16:3E:A8:6C:$prm_id
	--graphics vnc,port=$((5900+$prm_id)),listen=0.0.0.0
	--video virtio
	--noautoconsole
	--noreboot
	"
	
# @TODO ostype
# @TODO memory balloning for hot-plug and unplug
domstate=$(virsh dominfo $vmname 2>/dev/null)
if [ ! -z "$domstate" ] && [ "$prm_replace" -eq 0 ] ; then
	printf "ERROR: machine %s already existing and --replace was not given.\n" \
		"$vmname" >&2
	exit 1
elif [ ! -z "$domstate" ] ; then
	# replace means we delete any existing machine (=domain) with same name
	state="$(sed -n -e 's/State: *//p' <<<$domstate)"
	virsh shutdown "$vmname"
	virsh destroy "$vmname"
	virsh undefine "$vmname"
	#@TODO react on state of VM
	#case $state in
	#	"running" | "idle" )
	#	"paused" | "pmsuspended" )
	#	"in shutdown"
	#	"shut off" | "crashed" )
	#	* )
	#		printf "Unknown State \"%s\" of existing machine %s.\n" \
	#			" $state" "$vmname"
	#		exit 1
	#esac
   
fi	
echo virt-install $virt_prms
#DEBUG# virt-install --dry-run $virt_prms
virt-install $virt_prms
rc=$? ; if [ $rc -ne 0 ] ; then exit $rc ; fi

exit 0
