#! /bin/bash
#
# inst-coreos-functions.sh
#
# Install helper functions for CoreOS
#
# (C) 2014-2018 Stefan Schallenberg
#

##### inst-coreos_download ####################################################
function inst-coreos_download {
	local readonly BASEURL="https://stable.release.core-os.net/amd64-usr"
	local readonly CACHEBAS="/var/cache/coreos"

	if [ -e $CACHEBAS/current/version.txt ] ; then
		CACHE_VERSION=$( \
			gawk --field-separator '=' '/COREOS_VERSION=/ { print $2}' \
		       	< $CACHEBAS/current/version.txt)
	else
		CACHE_VERSION=""
	fi
	INET_VERSION=$(curl -L $BASEURL/current/version.txt | \
		gawk --field-separator '=' '/COREOS_VERSION=/ { print $2}' )

	if [ "$INET_VERSION" != "$CACHE_VERSION" ]; then
		printf  "Downloading CoreOS Version %s ... \n" "$INET_VERSION" >&2
		##### Now Download the newer version #########################
		local filelist="coreos_production_xen.README"
		filelist="$filelist,coreos_production_xen_image.bin.bz2"
		filelist="$filelist,coreos_production_xen_image.bin.bz2.sig"
		filelist="$filelist,coreos_production_xen_pvgrub.cfg"
		filelist="$filelist,coreos_production_xen_pygrub.cfg"
		filelist="$filelist,version.txt"
		filelist="$filelist,version.txt.sig"

		mkdir -p $CACHEBAS/$INET_VERSION >/dev/null
		curl -# -L -o "$CACHEBAS/$INET_VERSION/#1" \
			"$BASEURL/$INET_VERSION/{$filelist}" >&2
		rc=$?; if [ $rc -ne 0 ]; then
			printf "Error %s downloading CoreOS from %s to %s\n." \
				"$rc" \
				"$BASEURL/$INET_VERSION" \
			       	"$CACHEBAS/$INET_VERSION" >&2
			return 1
		fi
		rm $CACHEBAS/current >/dev/null
		ln -s $INET_VERSION $CACHEBAS/current >/dev/null
		if [ ! -z "$CACHE_VERION" ] ; then
			rm -rf $CACHEBAS/$CACHE_VERSION >/dev/null # delete old version 
		fi
	else
		printf  "Reusing cached CoreOS Version %s. \n" "$CACHE_VERSION" >&2
	fi

	printf "%s\n" "$CACHEBAS/current"
	return 0
}

##### download CloudOS Config Transpiler ######################################
function inst-coreos_download_ct {
	local readonly RELEASE_API_URL="https://api.github.com/repos/coreos/container-linux-config-transpiler/releases"
	local readonly CACHEBAS="/var/cache/coreos-ct"

	if [ ! -d "$CACHEBAS" ] ; then
		mkdir -p $CACHEBAS >/dev/null
	fi

	printf "Identifying coreos-ct latest release.\n" >&2
	local URL
	URL=$(curl -s "$RELEASE_API_URL" \
		| jq '.[0].assets[].browser_download_url' \
		| grep -- '-unknown-linux-gnu"' \
		| sed -e 's:^"::' -e 's:"$::' )
	rc=$?; if [ $rc -ne 0 ]; then
		printf "Error %s identifying CoreOS-ct at %s.\n" \
			"$rc" \
			"$RELEASE_API_URL" >&2
		return 1
	fi

	local readonly FNAME="$CACHEBAS/$(basename $URL)"
	local curlcacheopt=""
	if [ -e "$FNAME" ] ; then
		curlcacheopt="-z $FNAME"
	fi
	printf "Downloading coreos-ct.\n" >&2
	curl -L -o "$FNAME" $curlcacheopt "$URL" >&2
	rc=$?; if [ $rc -ne 0 ]; then
		printf "Error %s downloading CoreOS-ct from %s to %s\n." \
			"$rc" \
			"$URL" \
		       	"$CACHEBAS" >&2
		return 1
	fi
	chmod +x "$FNAME"

	printf "%s\n" "$FNAME"
}

##### ltrim #####
function ltrim {
	if [ $# -ne 1 ] ; then
		# Empty String results in empty string
		return
	fi

	# remove leading blanks
	printf "%s\n" "${1#"${1%%[![:space:]]*}"}"
	}

##### Read CoreOS Config and return list of YAML files #######################
function inst-coreos_read_ct-conf {
	# Parameter: Filename
	if [ ! -e "$1" ] ; then 
		printf "Internal Error: FileNotFound %s\n" "$1" >&2
		exit 1
	fi

	local line line_orig
	# global: FILES VARS
#	FILES=""

	while read line_orig ; do
		# ignore comments
		line=${line_orig%%#*}
		# remove leading blanks
		line="$(ltrim "$line")"

		if [ "${line:0:1}" == "@" ] ; then
			#If line startes with @ include another file
			inst-coreos_read_ct-conf "${line:1}"
		elif [[ "$line" == *"="* ]] ; then
			#If line contains = treat is as variable
			local varname=${line%%=*}
			local value=${line#*=}
			eval NEW_$varname=$value
			VARS="$VARS $varname"
		else
			words=( $line ) 
			if [ "${#words[@]}" -gt 1 ] ; then
				printf "Error: More than one filename per Line in %s: %s\n" "$1" "$line_orig" >&2
				return 1
			fi
			FILES="$FILES $line"
		fi
	done < "$1"

#	printf "%s\n" "$(ltrim "$FILES")"
	return 0
}

##### Core OS Config builder #################################################################
# Parm1: hostname - used also for config filenames
# Parm2: list of Environizing Parameters tp be replaced in templated. e.g. "HOSTNAME IP FQDN"
#        Values are expected in Variable NEW_<name>, e.g. NEW_HOSTNAME, NEW_IP, NEW_FQDN
# Output: Filename of ignition file
# Return Code: 0 if successfull.
# Messages are prtined to stderr if not successfull.
function inst-coreos_create_ct-conf {
	# Download coreos configurations transpiler (ct)
	local CT
	CT=$(inst-coreos_download_ct)
	rc=$?; if [ $rc -ne 0 ] ; then
		printf "Aborting install of machine %s.\n" "$1" >&2
		return 1
	fi

	# read config file
	local YAMLS
	# Attention: We use the global variabel VARS that may be modified by 
	# subroutines!
	VARS="$2"; FILES=""
	inst-coreos_read_ct-conf $CFG
	YAMLS=$FILES
	rc=$?; if [ $rc -ne 0 ] ; then
		printf "Could not read %s\nAborting install of machine %s.\n" "$CFG" "$1" >&2
		return 1
	fi
	if [ -z "$YAMLS" ] ; then
		printf "Empty File %s\nAborting install of machine %s.\n" "$CFG" "$1" >&2
		return 1
	fi

	# set Filenames
	tmpdir="$(realpath "$(dirname "$BASH_SOURCE")")/tmp"
	mkdir -p "$tmpdir" >/dev/null
	fname_ign="$tmpdir/$1.ignition"
	fname_yaml="$tmpdir/$1.yaml"
	JSONS=""

	# Write base information into merged YAML
	printf "# %s\n" "$fname_yaml" >$fname_yaml
	printf "#----- generated by %s from %s on %s\n" \
		"$(realpath $BASH_SOURCE)" \
		"$(realpath "$CFG")" "$(date)" >>$fname_yaml

	# prepare handling of template variables
	sed_template_opt=""
	for f in $VARS ; do
		eval value=\$NEW_$f
		if [ -z $value ] ; then
			printf "Template variabel NEW_%s not set or empty.\n" \
				"$f" >&2
			return 1
		fi
		printf "#----- Template-Var %s=%s\n" "$f" "$value" >>$fname_yaml
		sed_template_opt="$sed_template_opt -e s:\${$f}:${value//:/\\:}:" 
	done

	for f in $YAMLS; do
		if [ ! -e "$f" ] ; then 
			printf "File %s referenced in %s not found.\n"  \
				"$f" "$CFG" >&2
			return 1
		fi

		fname_this_input="$(realpath $(dirname $CFG)/$f)"
		fname_this_yaml="$tmpdir/$1-$(basename $f)"
		fname_this_json="$tmpdir/$1-$(basename $f .yaml).json"
		
		printf "#----- Referenced %s \n" \
			"$(ls -l $fname_this_input)" \
			>>$fname_yaml
		# substitute template variables
		sed $sed_template_opt \
		       	<"$fname_this_input" \
		       	>"$fname_this_yaml"
		rc=$?; if [ $rc -ne 0 ] ; then
			printf "Error replacing template vars of File %s referenced in %s.\n" \
				"$f" "$CFG" >&2
			return 1
		fi

		# Check that no variable is referenced without being defined
		if grep -q '${[^}]*}' $fname_this_yaml ; then
			printf "Error: Undefined variables %s used in File %s referenced in %s.\n" \
				"$(sed -n 's:^.*\(\${[^}]*}\).*$:\1:p' <$fname_this_yaml | tr '\n' ' ')" \
				"$f" "$CFG" >&2
			return 1
		fi

		# Transform YAML to JSON:
		python -c 'import sys,yaml,json; json.dump(yaml.load(sys.stdin), sys.stdout, indent=4)' \
			<"$fname_this_yaml" \
		       	>"$fname_this_json"
		rc=$?; if [ $rc -ne 0 ] ; then
			printf "Error transforming File %s to JSON (referenced in %s).\n" \
				"$f" "$CFG" >&2
			return 1
		fi
		JSONS="$JSONS $fname_this_json"
	done

	# Merge all JSONs:
	jqfilter=$(cat <<-"EOJQ"
		. as $src |
		reduce .[] as $i(
		      {error: $src, error_cnt: 0};

			# ignition part of config is not supported
			#              ignition: {
			#                      config: {
			#                               append: [],
			#                               replace: {} },
		        if $i.storage.disks
		                then .storage.disks += $i.storage.disks
		                         | del(.error[.error_cnt].storage.disks)
		                else . end |
		        if $i.storage.raid
		                then .storage.raid += $i.storage.raid
		                         | del(.error[.error_cnt].storage.raid)
		                else . end |
		        if $i.storage.filesystems
		                then .storage.filesystems += $i.storage.filesystems
		                         | del(.error[.error_cnt].storage.filesystems)
		                else . end |
		        if $i.storage.files
		                then .storage.files += $i.storage.files
		                         | del(.error[.error_cnt].storage.files)
		                else . end |
		        if .error[.error_cnt].storage | length == 0
		                then del(.error[.error_cnt].storage)
		                else . end |
		        if $i.systemd.units
		                then .systemd.units += $i.systemd.units
		                         | del(.error[.error_cnt].systemd.units)
		                else . end |
		        if .error[.error_cnt].systemd | length == 0
		                 then del(.error[.error_cnt].systemd)
		                else . end |
		        if $i.networkd.units
		                then .networkd.units += $i.networkd.units
		                         | del(.error[.error_cnt].networkd.units)
		                else . end |
		        if .error[.error_cnt].networkd | length == 0
		                 then del(.error[.error_cnt].networkd)
		                else . end |
		        if $i.passwd.users
		                then .passwd.users += $i.passwd.users
		                         | del(.error[.error_cnt].passwd.users)
		                else . end |
		        if $i.passwd.groups
		                then .passwd.groups += $i.passwd.groups
		                         | del(.error[.error_cnt].passwd.groups)
		                else . end |
		        if .error[.error_cnt].passwd | length == 0
		                 then del(.error[.error_cnt].passwd)
		                else . end |
		        if $i.etcd
		                then .etcd += $i.etcd
		                         | del(.error[.error_cnt].etcd)
		                else . end |
			if $i | has("flannel")
		                then .flannel += $i.flannel
		                         | del(.error[.error_cnt].flannel)
		                else . end |
		        if $i.docker
		                then .docker += $i.docker
		                         | del(.error[.error_cnt].docker)
		                else . end |
		        if $i.update
		                then .update += $i.update
		                         | del(.error[.error_cnt].update)
		                else . end |
		        if $i.locksmith
		                then .locksmith += $i.locksmith
		                         | del(.error[.error_cnt].locksmith)
		                else . end |
		        if .error[.error_cnt] | length == 0
		                 then del(.error[.error_cnt])
	                else 
			        .error_cnt += 1
			end
		        )
		| if .error | length > 0 then
			error(.error | tojson )
	       	else 
			del(.error) | del(.error_cnt) 
		end
		EOJQ
		)
	jq -s "$jqfilter" $JSONS >>$fname_yaml
	rc=$? ; if [ "$rc" -ne 0 ] ; then
		printf "Merging JSONs with jq failed. (rc=%s, Infiles=%s)\n" \
			"$rc" "$JSONS" >&2
		return 1
	fi

	# Now process our generated input with coreos config transpiler (ct)
       	$CT -strict -in-file $fname_yaml -out-file $fname_ign
	rc=$? ; if [ "$rc" -ne 0 ] ; then
		printf "CoreOS Config Transpiler failed. (rc=%s, Infile=%s)\n" \
			"$rc" "$fname_yaml" >&2
		return 1
	fi

	printf "%s\n" "$fname_ign"
	return 0
}

##### Core OS #################################################################
function inst-coreos_do {
	# Parameters: 
	#    1 - hostname
	#    2 - rootdev
	
	# make sure all needed tools are installed
	for pgm in kpartx lsblk dig jq ; do
		which "$pgm" >/dev/null || { echo "Missing $pgm" >&2 ; exit 1 ; }
		done
	python -c 'import sys,yaml,json' >/dev/null || \
		{ echo "Missing python module yaml or json" >&2 ; exit 1 ; }

	# check for existing config-file
	local readonly CFG="$(dirname $BASH_SOURCE)/$1.coreos-ct"
	if [ ! -e "$CFG" ] ; then 
		printf "missing Meta-Config for coreos-ct %s.\n" "$CFG"
		return 1
	fi

	# check that DNS entry exists and returns an IP adress
	# NB: We support only static IP configs!
	NEW_HOSTNAME="$1"
	NEW_FQDN="$NEW_HOSTNAME.intranet.nafets.de"
	NEW_IP=$(dig +short $NEW_FQDN)
        rc=$?
        if [ $rc -ne 0 ]; then
                printf "dig for %s returns %s. Aborting.\n" "$NEW_FQDN" "$rc"
		return 1
	elif [ -z "$NEW_IP" ] ; then
                printf "Cannot get IP for FQDN %s. Aborting.\n" "$NEW_FQDN"
		return 1
        fi

	CFG_IGN=$(inst-coreos_create_ct-conf "$1" "HOSTNAME FQDN IP")
        rc=$? ; if [ $rc -ne 0 ]; then
		return $rc
	fi

	echo "About to install CoreOS for $1"
	echo "Root-Device: $2"
	echo "Ignition Config File: $CFG_IGN"
	echo "Warning: All data on $2 will be DELETED!"
	read -p "Press Enter to Continue, use Ctrl-C to break."

	# instead of executing core-os install we do it our own
	#       because coreos-install cannot handle LVM volumes as disk and create
	#       partitions on it.
	# $CACHEDIR/coreos-install -o xen -C stable \
	#       -d "$2" \
	#       -c ~/tools/install/coreos/$1.yaml

	local readonly CACHEDIR=$(inst-coreos_download)

	bunzip2 --stdout \
		<$CACHEDIR/coreos_production_xen_image.bin.bz2 \
		>$2

	MNTDIR=$(mktemp --tmpdir -d coreos-install.XXXXXXXX)
	MNTNAME=$(lsblk -no NAME $2 | head -1)
	if [ -z $MNTNAME ] ; then
		echo "error identifying Disk with lsblk $2" >&2
		exit 1
	fi

	# Mount OEM partitiona and copy ignition file on it
	kpartx -sa /dev/mapper/$MNTNAME || { echo "Error in kpartx" >&2 ; exit 1 ; }
	OEMDEV=$(blkid -t "LABEL=OEM" -o device /dev/mapper/${MNTNAME}*)
	if [ -z $OEMDEV ] ; then
		echo "error identifying OEM-Disk with blkid on /dev/mapper/$MNT NAME" >&2
		exit 1
	fi
	mount $OEMDEV $MNTDIR || \
		{ echo "Could not mount $OEMDEV on $MNTDIR" >&2; exit 1 ; }

	cp "$CFG_IGN" $MNTDIR/coreos-install.json
	echo 'set linux_append="$linux_append coreos.config.url=oem:///coreos-install.json"' >> "$MNTDIR/grub.cfg"

	umount $MNTDIR
	kpartx -d /dev/mapper/$MNTNAME

	# Mount root partition and copy SSL private files it
	kpartx -sa /dev/mapper/$MNTNAME || { echo "Error in kpartx" >&2 ; exit 1 ; }
	ROOTDEV=$(blkid -t "LABEL=ROOT" -o device /dev/mapper/${MNTNAME}*)
	if [ -z $ROOTDEV ] ; then
		echo "error identifying Root-Disk with blkid on /dev/mapper/$MNTNAME" >&2
		exit 1
	fi
	mount $ROOTDEV $MNTDIR || \
		{ echo "Could not mount $ROOTDEV on $MNTDIR" >&2; exit 1 ; }
		
	install_nafets_files "$1" "$MNTDIR"

	umount $MNTDIR
	kpartx -d /dev/mapper/$MNTNAME
	
	return 0
}

##### main ####################################################################

# do nothing

