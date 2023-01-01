#!/usr/bin/env bash
#
# kvm-functions.sh
#
# Shell Functions to use KVM
#
# (C) 2018 Stefan Schallenberg

##### expect_value - print error if not ######################################
function kvm_expect_value () {
	parm="$1"
	value="$2"
	if [ -z "$value" ] ; then
		printf "Error: Parm %s needs value (e.g. %s==myvalue)\n" \
			"$1" "$1"
		return 1
	else
		return 0
	fi
}

##### parseParm - parse Parameters and set global variables ##################
function kvm_parseParm () {
	local -r def_memory="1024M"

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
		else
			value=""
		fi
		shift

		#DEBUG printf "DEBUG: parm %s value \"%s\"\n" "$parm" "$value" >&2
		case "$parm" in
			--disk | --root | --dev* )
				kvm_expect_value "$parm" "$value" || return 1
				prm_disk="$value"
				;;
			--disk2 )
				kvm_expect_value "$parm" "$value" || return 1
				prm_disk2="$value"
				;;
			--disk3 )
				kvm_expect_value "$parm" "$value" || return 1
				prm_disk3="$value"
				;;
			--mem )
				kvm_expect_value "$parm" "$value" || return 1
				prm_mem="$value"
				;;
			--cpu )
				kvm_expect_value "$parm" "$value" || return 1
				prm_cpu="$value"
				;;
			--id )
				kvm_expect_value "$parm" "$value" || return 1
				prm_id="$value"
				;;
			--virt )
				kvm_expect_value "$parm" "$value" || return 1
				prm_virt="$value"
				;;
			--os )
				kvm_expect_value "$parm" "$value" || return 1
				prm_os="$value"
				;;
			--sound )
				kvm_expect_value "$parm" "$value" || return 1
				prm_sound="$value"
				;;
			--auto )
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
			--net | --net[1-8] )
				kvm_expect_value "$parm" "$value" || return 1
				eval "prm_${parm:2}='$value'"
				;;
			--cpuhost )
				prm_cpuhost="${value:-1}"
				;;
			--arch )
				kvm_expect_value "$parm" "$value" || return 1
				prm_arch="$value"
				;;
			--boot )
				kvm_expect_value "$parm" "$value" || return 1
				prm_boot="$value"
				;;
			*)
				printf "Error: unknown Parameter %s with value %s\n" \
					"$parm" "$value"
				return 1
		esac
	done

	return 0
}

##### getDefaultAuto #########################################################
# set Default Auto-Start value
# 0 for machine name *Test, 1 otherwise
function kvm_getDefaultAuto () {
	vmname="$1"
	if [[ "$vmname" == *Test ]] ; then
		printf "0\n"
	else
		printf "1\n"
	fi

	return 0
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
#   --disk=<device> [optional, autodetected]
#   --disk2=<device> [optional, autodetected]
#   --disk3=<device> [optional, default=empty]
#   --mem=<size> [default=1024MB]
#   --cpu=<nr of config> [optional, default=empty]
#         example: --cpu=3,cpuset=2-3
#   --id=internal ID, needs to be unique in whole system
#   --replace replace existing VMs [default=no]
#   --auto=1 [default=1] auto-start VM at boot
#   --dry-run done really execute anything.
#   --net=<backend> [optional, autodetected]
#   --net2=<backend> [optional, default=empty]
#   --net3=<backend> [optional, default=empty]
#   --net4=<backend> [optional, default=empty]
#   --net5=<backend> [optional, default=empty]
#   --net6=<backend> [optional, default=empty]
#   --net7=<backend> [optional, default=empty]
#   --net8=<backend> [optional, default=empty]
#   --cpuhost allow access to host CPU, use only for nexted virtualization!
function kvm_create-vm () {
	# Set Default values
	local prm_mem="768"
	local prm_cpu=""
	local prm_replace="0"
	local prm_dryrun="0"
	local prm_virt="kvm"
	local prm_efi="0"
	local prm_auto
	local prm_id
	local prm_disk
	local prm_disk2
	local prm_disk3
	local prm_os
	local prm_sound
	local vmname
	local prm_net
	local prm_net2
	local prm_net3
	local prm_net4
	local prm_net5
	local prm_net6
	local prm_net7
	local prm_net8
	local prm_cpuhost="0"
	local prm_arch
	local prm_boot
	local diskbustype="virtio" # will be modified for arch architecture to scsi
	local nettype="virtio" # will be modified for arch architectures to smc91c111
	local videotype="virtio" # will be modified for arch architectures
	rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi

	# Parse Parameters
	kvm_parseParm "$@"
	rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi

	# Calculate Domain ID to be used as unique number where needed
	# e.g. in MAC adress
	if [ -z "$prm_id" ] ; then
		printf "No ID given (--id) for machine %s.\n" \
				"$vmname" >&2
		return 1
	fi

	# Ensure Disk Device is known
	if [ -z "$prm_disk" ] ; then
		printf "No Disk given (--disk) for machine %s.\n" \
			"$vmname" >&2
		return 1
	fi

	# Auto-Detect OS if not given on commandline
	if [ -z "$prm_os" ] ; then
		prm_os=$(kvm_getDefaultOS $vmname)
		rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi
	fi

	# Auto-Detect Auto-start if not given on commandline
	if [ -z "$prm_auto" ] ; then
		prm_auto="$(kvm_getDefaultAuto "$vmname")"
		rc=$?; if [ "$rc" -ne 0 ] ; then return $rc; fi
	fi

	#set Disk Bus device depending on Architecture
	if [ "$prm_arch" == "armv6l" ] ; then
		diskbustype="scsi" # sd does work for definition,  but not when domain is started
		# old: nettype="smc91c111"
		nettype="virtio"
		videotype="vga"
	else
		diskbustype="virtio"
		nettype="virtio"
		videotype="virtio"
	fi

	# Tell user what we do
	local prefix_dryrun=""
	[ "$prm_dryrun" -ne 0 ] && prefix_dryrun="Dryrun-"
	printf "%s: %sInstalling machine %s (ID=%s)\n" \
		"$(basename $BASH_SOURCE .sh)" \
		"$prefix_dryrun" \
		"$vmname" \
		"$prm_id"
	printf "\tarch %s\n" "${prm_arcg:-<default>}"
	printf "\tefi BIOS %s\n" "$prm_efi"
	printf "\tBoot %s\n" "${prm_boot:-<none>}"
	printf "\tOS %s\n" "${prm_os:-<default>}"
	printf "\tmemory %s\n" "$prm_mem"
	printf "\tcpu %s (host=%s)\n" "$prm_cpu" "$prm_cpuhost"
	printf "\tboot+root-disk %s\n" "$prm_disk"
	printf "\tdisk2: %s\n" "${prm_disk2:-<none>}"
	printf "\tdisk3: %s\n" "${prm_disk3:-<none>}"
	printf "\tnet %s\n" "$prm_net"
	printf "\tnet2 %s\n" "${prm_net2:-<none>}"
	printf "\tnet3 %s\n" "${prm_net3:-<none>}"
	printf "\tnet4 %s\n" "${prm_net4:-<none>}"
	printf "\tnet5 %s\n" "${prm_net5:-<none>}"
	printf "\tnet6 %s\n" "${prm_net6:-<none>}"
	printf "\tnet7 %s\n" "${prm_net7:-<none>}"
	printf "\tnet8 %s\n" "${prm_net8:-<none>}"
	printf "\tVirtualisation: %s\n" "$prm_virt"
	printf "\tAutoStart: %s\n" "$prm_auto"
	printf "\tSound: %s\n" "${prm_sound:-<none>}"

	# Action !
	local virt_prms="
		--check disk_size=off
		--name $vmname
		--virt-type $prm_virt
		--memory $prm_mem
		--vcpus=$prm_cpu
		--import
		--disk $prm_disk,format=raw,bus=$diskbustype,size=10
		--events on_crash=restart
		--noautoconsole
		--noreboot
		--osinfo=require=off
		"
	if [ ! -z "$prm_disk2" ] ; then
		virt_prms="$virt_prms
			--disk $prm_disk2,format=raw,bus=$diskbustype,size=10
			"
	fi
	if [ ! -z "$prm_disk3" ] ; then
		virt_prms="$virt_prms
			--disk $prm_disk3,format=raw,bus=$diskbustype,size=10
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
	if [ "$prm_net" == "none" ] ; then
		virt_prms="$virt_prms
			--net none
			"
	else
		for n in "" 2 3 4 5 6 7 8 ; do
			eval thisprmnet=\$\{prm_net$n\}
			if [ ! -z "$thisprmnet" ] ; then
				thisprmnet_src=${thisprmnet%%,*}
				thisprmnet_type=${thisprmnet_src%%:*}
				thisprmnet_type=${thisprmnet_type:-defaulttype}
				thisprmnet_src=${thisprmnet_src##*:}
				thisprmnet_mac=${thisprmnet##*,}
				if [ -z $thisprmnet_src ] || [ -z %thisprmnet_mac ] ; then
					printf "invalid net parm %s for net%s.\n" "$thisprmnet" "$n"
					return 1
				elif
						[ "$thisprmnet_type" != "net" ] &&
						[ "$thisprmnet_type" != "direct" ] ; then
					printf "invalid net parm %s for net%s (type not net,direct)\n" \
						"$thisprmnet" "$n"
					return 1
				fi

				if [ "$thisprmnet_type" == "net" ] ; then
					virt_prms="$virt_prms
						--network network=$thisprmnet_src"
				elif [ "$thisprmnet_type" == "direct" ] ; then
					virt_prms="$virt_prms
						--network type=direct,source=$thisprmnet_src,source_mode=bridge"
				else
					return 1 # this should never be reached
				fi
				virt_prms="$virt_prms,model=$nettype,mac=$thisprmnet_mac,trustGuestRxFilters=yes"
			fi
		done
	fi
	if [ "$prm_cpuhost" == "1" ] ; then
		virt_prms="$virt_prms
			--cpu host-passthrough
			"
	elif [ -z "$prm_cpuhost" ] ; then
		virt_prms="$virt_prms
			--cpu host
			"
	fi
	if [ ! -z "$prm_arch" ] ; then
		virt_prms="$virt_prms
			--arch $prm_arch
			"
		if [ "$prm_arch" == "armv6l" ] ; then
			virt_prms="$virt_prms
				--cpu arm1176
				--machine versatilepb
				"
		else
			virt_prms="$virt_prms
				--graphics vnc,port=$((5900+$prm_id)),listen=0.0.0.0
				--video $videotype
				"
		fi
	fi
	# !!! --boot must be last to avoid deleting the ''
	if [ "$prm_efi" == "1" ] ; then
		virt_prms="$virt_prms
			--boot uefi
			"
	elif [ ! -r "$prm_boot" ] ; then
		virt_prms="$virt_prms
			--boot \"$prm_boot\"
			"

	fi
	# @TODO ostype
	# @TODO memory balloning for hot-plug and unplug
	local domstate=$(virsh dominfo $vmname 2>/dev/null)
	if [ "$prm_dryrun" -ne 0 ] ; then
		true
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
		eval virt-install $virt_prms
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

	if		[ -z "$domstate" ] ||
			[ "$domstate" == " " ] ; then
		# Domain is not existing
		return 0
	elif	[ "$domstate" == "running" ] ||
			[ "$domstate" == "idle" ] ; then
		virsh shutdown "$vmname"
		virsh destroy "$vmname"
		virsh undefine --nvram "$vmname"
	elif	[ "$domstate" == "paused" ] ||
			[ "$domstate" == "pmsuspended" ] ||
			[ "$domstate" == "in shutdown" ] ; then
		virsh destroy "$vmname"
		virsh undefine --nvram "$vmname"
	elif	[ "$domstate" == "shut off" ] ||
			[ "$domstate" == "crashed" ] ; then
		virsh undefine --nvram "$vmname"
	else
		printf "Unknown State \"%s\" of existing machine %s.\n" \
			" $state" "$vmname" >&2
		return 1
	fi
}

##### kvm_start-vm ##########################################################
# Parameters:
# 1 - machinename [mandatory]
# 2 - DNS name of machine [optional, default=machinename ]
# 2 - Timeout to wait for machine to appear in seconds [optional, 60]
function kvm_start_vm {
	if [ -z "$1" ] ; then
		printf "Error: no machine name supplied\n" >&2
		return 1
	fi
	local -r vmname="$1"
	local -r dnsname="${2:-$vmname}"
	local -r sleepMax=${3:-60}
	local -r waitDNS=${4:-0}

	local -r sleepFirst=5
	local -r sleepNext=5

	local slept=0 # beginning

	ping -c 1 -W 1 "$dnsname"; rc=$?
	case $rc in
		0)
			printf "Error: %s is running and replying to ping at %s\n" \
				"$vmname" "$dnsname"
			return 1
			;;
		1)
			# expected
			;;
		*)
			if [ "$waitDNS" == "0" ] ; then
				printf "Error: cannot ping %s %s\n" \
					"$vmname" "$dnsname"
				return 1
			else
				printf "Warning: cannot ping %s %s\n" \
					"$vmname" "$dnsname"
			fi
			;;
	esac

	printf "Starting virtual Machine %s\n" "$vmname"
	virsh start $vmname || return 1

	printf "Waiting initial %s seconds for machine %s to appear (%s/%s)\n" \
		"$sleepFirst" "$vmname" "$slept" "$sleepMax"
	sleep $sleepFirst ; slept=$(( $slept + $sleepFirst ))

	while [ "$slept" -lt "$sleepMax" ] ; do
		[ ! -z "$(dig +short $dnsname)" ] &&
		ping -c 1 -W 1 "$dnsname" &&
		ssh -o StrictHostKeyChecking=no -n "$dnsname" &&
		vmstatus=$(ssh -o StrictHostKeyChecking=no "$dnsname" \
			<<-EOF |
			if [ -e /usr/bin/systemctl ] ; then
				/usr/bin/systemctl is-system-running
			else
				echo "running" ;
			fi
			EOF
			tail -1) &&
		if [ "$vmstatus" == "running" ] ; then
			return 0
		elif [ "$vmstatus" == "degraded" ] ; then
			printf "ERROR: machine %s did not completely start (degraded)\n" \
				"$MNAME"
			printf "Following Services could not be started:\n"
			ssh -o StrictHostKeyChecking=no -q "$dnsname" <<-EOF
				/usr/bin/systemctl --failed --no-pager --plain --no-legend --full
				EOF
			return 1
		fi

		printf "Waiting another %s seconds for machine %s to appear (%s/%s) %s\n" \
			"$sleepNext" "$vmname" "$slept" "$sleepMax" "$vmstatus"
		sleep $sleepNext ; slept=$(( $slept + $sleepNext ))
	done

	printf "ERROR: Timed out waiting %s seconds for machine %s\n" \
		"$sleepMax" "$MNAME"

	return 1
}

##### Main ###################################################################
# do nothing
