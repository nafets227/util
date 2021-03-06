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
		fname="$(dirname $caller)/$1"
	fi

	if [ ! -r $fname ] ; then
		printf "util_loadfunc-or-exit: file %s not readable\n" \
			"$fname" >&2
		exit 99
	fi

	. $fname
	rc=$?; if [ $rc -ne 0 ] ; then
		printf "util_loadfunc-or-exit: file %s return Error %s\n" \
			"$fname" "$rc" >&2
		exit 99
	fi

	return 0
}

##### util_download  #########################################################
function util_download {
	local readonly URL="$1"
	local readonly MY_CACHEDIR=${UTIL_CACHEDIR:-"/var/cache/nafets-util"}
	local readonly CACHFIL="${2:-$UTIL_CACHEDIR/$(basename $URL)}"

	printf "Downloading %s to %s\n" "$URL" "$CACHFIL" >&2

	test -d "$(dirname $CACHFIL)" ||
	mkdir -p "$(dirname $CACHFIL)" ||
	return 1

	for i in 1 2 3 ; do
		if [ ! -f $CACHFIL ] ; then
			curl \
				--fail \
				--location \
				--remote-time \
				--output $CACHFIL \
				$URL \
				>&2
			rc=$?
		else
			curl \
				--fail \
				--location \
				--remote-time \
				--output $CACHFIL \
				--time-cond $CACHFIL \
				$URL \
				>&2 &&
			curl \
				--fail \
				--location \
				--remote-time \
				--output $CACHFIL \
				--time-cond -$CACHFIL \
				$URL \
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
	if [ ! -z "${fname/*:*/}" ] ; then
		# fname contains no ":" so its already local
		printf "%s\n" "$fname"
	elif [ "${fname#http://*#}" ] || [ -z "${fname#https://*#}" ] ; then
		# fname begins with "http://" or "https://" so its remote http(s)
		local lfname
		lfname=$(util_download $fname) || return 1
		printf "%s\n" "$lfname"
	else
		# fname contains ":" so its remote via scp
		scp $fname /tmp/$(basename $fname) || return 1
		printf "%s\n" "/tmp/$(basename $fname)"
	fi

	return 0
}

##### util-getIP #############################################################
function util-getIP {
	local result
	result=$(dig +short $1)
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

##### Main ###################################################################
# do nothing
