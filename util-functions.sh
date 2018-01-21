#!/bin/bash
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

##### Main ###################################################################
# do nothing

