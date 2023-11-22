#!/usr/bin/env bash
#
# util-functions.sh
#
# Collection of general functions.
#
# (C) 2018 Stefan Schallenberg
#

##### ltrim ##################################################################
function ltrim {
	if [ $# -ne 1 ] ; then
		# Empty String results in empty string
		return
		fi

	# remove leading blanks
	printf "%s\n" "${1#"${1%%[![:space:]]*}"}"
}

##### util_loadfunc-or-exit ##################################################
function util_loadfunc-or-exit {
	caller="${BASH_SOURCE[1]}"

	if [ "$#" -ne 1 ] ; then
		printf "util_loadfunc-or-exit: wrong # parms: %s (exp=1)\n" \
			"$#" >&2
		exit 99
	elif [ -z "$1" ] ; then
		printf "util_loadfunc-or-exit: unexpected empty parm\n" >&2
		exit 99
	fi

	local fname=""
	if [ "${1:1:1}" == "/" ] ; then # absolute path given
		fname="$1"
	else
		fname="$(dirname "$caller")/$1"
	fi

	if [ ! -r "$fname" ] ; then
		printf "util_loadfunc-or-exit: file %s not readable\n" \
			"$fname" >&2
		exit 99
	fi

	#shellcheck disable=SC1090 # no chance to lint the included file here
	. "$fname"
	rc=$?; if [ $rc -ne 0 ] ; then
		printf "util_loadfunc-or-exit: file %s return Error %s\n" \
			"$fname" "$rc" >&2
		exit 99
	fi

	return 0
}

##### util_download  #########################################################
function util_download {
	local -r URL="$1"
	local -r MY_CACHEDIR=${UTIL_CACHEDIR:-"/var/cache/nafets-util"}
	local -r CACHFIL="${2:-$MY_CACHEDIR/$(basename "$URL")}"

	printf "Downloading %s to %s\n" "$URL" "$CACHFIL" >&2

	test -d "$(dirname "$CACHFIL")" ||
	mkdir -p "$(dirname "$CACHFIL")" ||
	return 1

	for i in 1 2 3 ; do
		echo "$i" >/dev/null # tell shellcheck var i is used
		if [ ! -f "$CACHFIL" ] ; then
			curl \
				--fail \
				--location \
				--remote-time \
				--output "$CACHFIL" \
				"$URL" \
				>&2
			rc=$?
		else
			curl \
				--fail \
				--location \
				--remote-time \
				--output "$CACHFIL" \
				--time-cond "$CACHFIL" \
				"$URL" \
				>&2 &&
			curl \
				--fail \
				--location \
				--remote-time \
				--output "$CACHFIL" \
				--time-cond "-$CACHFIL" \
				"$URL" \
				>&2
			rc=$?
		fi
		if [ "$rc" == "0" ] ; then
			break
		fi
	done
	if [ "$rc" != "0" ] ; then
		return 1
	fi

	printf "%s\n" "$CACHFIL"
	return 0
}

#### util_make-local #########################################################
function util_make-local {
	fname="$1"
	if [ -z "$fname" ] ; then
		printf "Internal error: got %s parms (exp>1)\n" "$#"
		return 1
	fi

	#----- Action -------------------------------------------------------
	if [ -n "${fname/*:*/}" ] ; then
		# fname contains no ":" so its already local
		if [ ! -r "$fname" ] ; then
			return 1
		fi
		printf "%s\n" "$fname"
	elif [ "${fname#http://*#}" ] || [ -z "${fname#https://*#}" ] ; then
		# fname begins with "http://" or "https://" so its remote http(s)
		local lfname
		lfname=$(util_download "$fname") || return 1
		printf "%s\n" "$lfname"
	else
		# fname contains ":" so its remote via scp
		scp "$fname" "/tmp/$(basename "$fname")" || return 1
		printf "%s\n" "/tmp/$(basename "$fname")"
	fi

	return 0
}

##### util_verifypwfile ######################################################
function util_verifypwfile {
	local pwfile="$1"

	if [ -z "$pwfile" ] ; then
		printf "util_verifypwfile: unexpected empty parm\n" >&2
		return 1
	elif [ ! -f "$CERT_PRIVATE_DIR/$pwfile" ] ; then
		printf "util_verifypwfile: fiel %s does not exist\n" \
			"$CERT_PRIVATE_DIR/$pwfile" >&2
		return 1
	elif cat -e "$CERT_PRIVATE_DIR/$pwfile" | grep -q '\$' ; then
		printf "Error: password File %s contains trailing newline\n" \
			"$CERT_PRIVATE_DIR/$pwfile" >&2
		return 1
	fi

	return 0
}

##### util-getIP #############################################################
function util-getIP {
	local result
	result=$(dig +short "$1")
	rc=$?
	if [ $rc != "0" ] ; then
		printf "Error getting IP of %s.\n" "$1" >&2
		return 1
	elif [ -z "$result" ] ; then
		printf "DNS name %s not defined.\n" "$1" >&2
		return 1;
	fi

	printf "%s\n" "$result"
	return 0
}

##### util-get1IP #############################################################
function util-get1IP {
	set -o pipefail

	util-getIP "$1" | tail -1

	return $?
}

function util_updateConfig {
	local -r fname=$1
	local -r varname=$2
	local -r value=$3

	# For explanation on sed syntax see
	# https://stackoverflow.com/questions/15965073
	#shellcheck disable=SC2016
	sed -i -r -e \
		'/^([[:blank:]]*)(#?)(#*)([[:blank:]]*'"$varname"'[[:blank:]]*=[[:blank:]]*)(.*)$/'" \
		"'{s::\1#\3\4\5\n\1\4'"$value"':;h}'" \
		"';${x;/./{x;q0};x;q100}' \
		"$fname"
	case $? in
		0)
			return 0
			;;
		100)
			printf "%s(%s): Error %s not found in %s\n" \
				"${FUNCMANE[0]}" "${FUNCNAME[1]}" "$varname" "$fname"
			return 100
			;;
		*)
			printf "%s: Internal error. sed-RC=%s (\"%s\", \"%s\", \"%s\")\n" \
				"${FUNCNAME[0]}" "$?" "$fname" "$varname" "$value"
			return 1
			;;
	esac
}

function util_getConfig {
	local -r fname=$1
	local -r varname=$2

	sed -n -r -e \
		's/^[[:blank:]]*'"$varname"'[[:blank:]]*=[[:blank:]]*(.*)$/\1/p' \
		"$fname" \
	|| return 1

	return 0
}

##### Main ###################################################################
# do nothing
