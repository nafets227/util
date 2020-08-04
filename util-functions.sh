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

##### util_download  #########################################################
function util_download {
	local readonly URL="$1"
	local readonly CACHFIL="${2:-/var/cache/nafets-util/$(basename $URL)}"

        printf "Downloading %s to %s\n" "$URL" "$CACHFIL" >&2

	test -d "$(dirname $CACHFIL)" ||
		mkdir -p "$(dirname $CACHFIL)" ||
		return 1

        if [ -f $CACHFIL ] ; then
                CURL_OPT="--time-cond $CACHFIL --time-cond -$CACHFIL"
        else
                CURL_OPT=""
        fi
        curl \
                --location \
                --remote-time \
                --output $CACHFIL \
                $CURL_OPT \
                $URL \
		>&2 \
        || return 1

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
	else
		# fname ontains A ":" so its remote
		scp $fname /tmp/$(basename $fname) || return 1
		printf "%s\n" "/tmp/$(basename $fname)"
	fi

	return 0
}

##### Main ###################################################################
# do nothing

