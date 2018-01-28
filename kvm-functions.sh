#!/bin/bash
#
# kvm-functions.sh
#
# Shell Functions to use KVM
#
# (C) 2018 Stefan Schallenberg

##### parseParm - parse Parameters and set global variables ##################
function kvm_parseParm () {
	local readonly def_memory="1024M"
	
	if [ "$#" -lt 1 ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	vmname="$1"
	shift

	local value
	local value_present

	while [ $# -gt 0 ] ; do
		parm="${1%%=*}"
		if [ "$1" != "$parm" ] ; then # contains =
			value=${1#*=}
			value_present=1
		else
			value=""
			value_present=0
		fi
		shift
		
		#DEBUG printf "DEBUG: parm %s value \"%s\"\n" "$parm" "$value" >&2
		case "$parm" in
			--disk | --boot | --root | --dev* )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_disk="$value"
				;;
			--disk2 )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_disk2="$value"
				;;
			--disk3 )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_disk3="$value"
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
			--os )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_os="$value"
				;;
			--sound )
				if [ "$value_present" -eq 0 ] ; then value="$1"; shift; fi
				prm_sound="$value"
				;;
			--auto )
				if [ "$value_present" -eq 0 ] && [ "${1:0:2}" != "--" ] ; then
				       	value="$1"
				       	shift
				fi
				prm_auto="${value:-1}"
				;;
			--replace )
				prm_replace="${value:-1}"
				;;
			--dry-run )
				prm_dryrun="${value:-1}"
				;;
			--efi )
				prm_efi="${value:-1}"
				;;
			*)
				printf "Error: unknown Parameter %s with value %s\n" \
					"$parm" "$value"
				return 1				
		esac
	done

	return 0
}

##### getDefaultDisk #########################################################
# Parameter:
#   1 - virtual machine name
function kvm_getDefaultDisk () {
	vmname="$1"
	if [ -b /dev/vg-sys/$vmname-sys ] ; then
		printf "/dev/vg-sys/%s-sys\n" "$vmname"
	elif [ -e /var/lib/libvirt/images/$vmname.raw ] ; then
		printf "/var/lib/libvirt/images/%s.raw\n" "$vmname"
	else
		printf "No Default Device found for machine %s. Candidates:\n" "$vmname" >&2
		printf "\t/dev/vg-sys/%s-sys\n" "$vmname" >&2
		printf "\t/var/lib/libvirt/images/%s.raw\n" "$vmname" >&2
		return 1		
	fi		
} 

##### getDefaultDisk2 ########################################################
# Parameter:
#   1 - virtual machine name
function kvm_getDefaultDisk2 () {
	vmname="$1"
	for f in \
			/dev/vg-sys/$vmname-data \
			/dev/xen-data/$vmname-data \
			/dev/data/$vmname-data \
			; do
		if [ -b $f ] ; then
			printf "%s\n" "$f"
			return 0
		fi
	done

	if [ -e /var/lib/libvirt/images/$vmname-data.raw ] ; then
		printf "/var/lib/libvirt/images/%s-data.raw\n" "$vmname"
	else
		printf "No Default Disk2 found.\n" >&2
		return 0
	fi
}

##### getNetworkDevice #######################################################
# choose Network Device
# we use the first non-loopback device of "IP link show"
function kvm_getNetworkDevice () {
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
function kvm_getDefaultID() {
	if [ "$#" -lt 1 ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	local vmname="$1"
	
	case $vmname in
		vDom   ) id="01" ;;
		#Octopus)id="03" ;; # SATIP HW appliance, save the ID here
		xen1 | vXen1 | kvm1 | vKvm1 | vPhys1 )
		         id="05" ;;
		xen2 | vXen2 | kvm2 | vKvm2 | vPhys2 )
		         id="06" ;;

		vVdr   ) id="10" ;;
		vSrv   ) id="11" ;;
		vMgmt  ) id="12" ;;
		vWin   ) id="13" ;;
		
		vTest  ) id="17" ;;
		
		vKube1 ) id="21" ;;
		vKube2 ) id="22" ;;
		vKube3 ) id="23" ;;
		
	esac

	if [ -z "$id" ] ; then
		return 1
	else
		printf "%s\n" "$id"
		return 0
	fi
	}

##### getDefaultOS ###########################################################
# Parameters:
# 1 - machinename [mandatory]
function kvm_getDefaultOS () {
	if [ "$#" -lt 1 ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	local vmname="$1"

	case $vmname in
# currently all auto.-detection is disabled
# if we want a specific OS it has to be given by commandline
#		vWin   ) os="win10" ;;
#		vKube* ) os="" ;; # CoreOS: no entry, use blank
		*      ) os="" ;; # ArchLinux: no entry, use blank
	esac

	printf "%s\n" "$os"
	return 0
}

##### kvm_create-vm ##########################################################
# Parameters:
# 1 - machinename [mandatory]
# Options:
#   --disk <device> [optional, autodetected]
#   --disk2 <device> [optional, autodetected]
#   --disk3 <device> [optional, default=empty]
#   --mem <size> [default=1024MB]
#   --cpu <nr of config> [default: 3,cpuset=2-3]
#         CPU #0 is intended for physical machine only
#         CPU #1 is intende vor Vdr only
#   --id   internal ID, needs to be unique in whole system
#         [default: use a static mapping table inside this script]
#   --replace replace existing VMs [default=no]
#   --auto [default=1] auto-start VM at boot
#   --dry-run done really execute anything.
function kvm_create-vm () {
	# Set Default values
	local prm_mem="768"
	local prm_cpu="3,cpuset=2-3"
	local prm_replace="0"
	local prm_dryrun="0"
	local prm_virt="kvm"
	local prm_auto="1"
	local prm_efi="0"
	local prm_id
	local prm_disk
	local prm_disk2
	local prm_disk3
	local prm_os
	local prm_sound
	local vmname
	local netdev=$(kvm_getNetworkDevice)
	rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi

	# Parse Parameters
	kvm_parseParm "$@"
	rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi

	# Calculate Domain ID to be used as unique number where needed
	# e.g. in MAC adress
	if [ -z "$prm_id" ] ; then
		prm_id=$(kvm_getDefaultID $vmname)
		rc=$?; if [ "$rc" -ne 0 ] ; then
			printf "No ID given (--id) and no Default found for machine %s.\n" \
				"$vmname" >&2
			return $rc;
		fi
	fi

	# Find Device if not given on commandline
	if [ -z "$prm_disk" ] ; then
		prm_disk=$(kvm_getDefaultDisk $vmname)
		rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi
	fi

	# Auto-Detect second Disk if not given on commandline
	if [ -z "$prm_disk2" ] ; then
		prm_disk2=$(kvm_getDefaultDisk2 $vmname)
		rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi
	fi

	# Auto-Detect OS if not given on commandline
	if [ -z "$prm_os" ] ; then
		prm_os=$(kvm_getDefaultOS $vmname)
		rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi
	fi

	# Tell user what we do
	local prefix_dryrun=""
	[ "$prm_dryrun" -ne 0 ] || prefix_dryrun="Dryrun-"
	printf "%s: %sInstalling machine %s (ID=%s)\n" \
		"$(basename $BASH_SOURCE .sh)" \
		"$prefix_dryrun" \
		"$vmname" \
		"$prm_id"
	printf "\tefi BIOS %s\n" "$prm_efi"
	printf "\tOS %s\n" "${prm_os-<default>}"
	printf "\tmemory %s\n" "$prm_mem"
	printf "\tcpu %s\n" "$prm_cpu"
	printf "\tboot+root-disk %s\n" "$prm_disk"
	printf "\tdisk2: %s\n" "${prm_disk2-<none>}"
	printf "\tdisk3: %s\n" "${prm_disk3-<none>}"
	printf "\tnetwork %s\n" "$netdev"
	printf "\tVirtualisation: %s\n" "$prm_virt"
	printf "\tAutoStart: %s\n" "$prm_auto"
	printf "\tSound: %s\n" "${prm_sound-<none>}"

	# Action !
	local virt_prms="
		--name $vmname
		--virt-type $prm_virt
		--memory $prm_mem
		--vcpus=$prm_cpu
		--cpu host
		--import
		--disk $prm_disk,format=raw,bus=virtio
		--network type=direct,source=$netdev,source_mode=bridge,model=virtio,mac=00:16:3E:A8:6C:$prm_id
		--graphics vnc,port=$((5900+$prm_id)),listen=0.0.0.0
		--video virtio
		--events on_crash=restart
		--noautoconsole
		--noreboot
		"
	if [ ! -z "$prm_disk2" ] ; then
		virt_prms="$virt_prms
			--disk $prm_disk2,format=raw,bus=virtio
			"
	fi
	if [ ! -z "$prm_disk3" ] ; then
		virt_prms="$virt_prms
			--disk $prm_disk3,format=raw,bus=virtio
			"
	fi
	if [ "$prm_auto" == "1" ] ; then
		virt_prms="$virt_prms
			--autostart
			"
	fi
	if [ ! -z "$prm_os" ] ; then
		virt_prms="$virt_prms
			--os-variant $prm_os
			"
	fi
	if [ ! -z "$prm_sound" ] ; then
		virt_prms="$virt_prms
			--sound $prm_sound
			"
	fi
	if [ "$prm_efi" == "1" ] ; then 
		virt_prms="$virt_prms
			--boot loader=/usr/share/ovmf/x64/OVMF_CODE.fd,loader_ro=yes,loader_type=pflash,nvram_template=/usr/share/ovmf/x64/OVMF_VARS.fd,loader_secure=no
			"
	fi
	
	# @TODO ostype
	# @TODO memory balloning for hot-plug and unplug
	local domstate=$(virsh dominfo $vmname 2>/dev/null)
	if [ "$prm_dryrun" -ne 0 ] ; then
		/bin/true
	elif [ ! -z "$domstate" ] && [ "$prm_replace" -eq 0 ] ; then
		printf "ERROR: machine %s already existing and --replace was not given.\n" \
			"$vmname" >&2
		exit 1
	else
	       kvm_delete-vm $vmname
	       # We dont honor return code here!
	fi
	echo virt-install $virt_prms

	if [ "$prm_dryrun" -ne 0 ] ; then
		virt-install --dry-run $virt_prms
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc ; fi
	else
		virt-install $virt_prms
		rc=$? ; if [ $rc -ne 0 ] ; then return $rc ; fi
	fi

	return 0
}

##### kvm_delete-vm ##########################################################
# Parameters:
# 1 - machinename [mandatory]
function kvm_delete-vm {
	if [ -z "$1" ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	vmname="$1"
	
	local domstate=$(virsh domstate $vmname 2>/dev/null)

	if [ -z "$domstate" ] ||
	   [ "$domstate" == " " ] ; then
		# Domain is not existing
		return 0
	elif [ "$domstate" == "running" ] ||
	     [ "$domstate" == "idle" ] ; then
		virsh shutdown "$vmname"
		virsh destroy "$vmname"
		virsh undefine --nvram "$vmname"
	elif [ "$domstate" == "paused" ] ||
	     [ "$domstate" == "pmsuspended" ] ||
	     [ "$domstate" == "in shutdown" ] ; then
		virsh destroy "$vmname"
		virsh undefine --nvram "$vmname"
	elif [ "$domstate" == "shut off" ] ||
	     [ "$domstate" == "crashed" ] ; then
		virsh undefine --nvram "$vmname"
	else
		printf "Unknown State \"%s\" of existing machine %s.\n" \
			" $state" "$vmname" >&2
		return 1
	fi
   
}

##### Main ###################################################################

# do nothing

