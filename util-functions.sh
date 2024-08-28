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
		printf "util_verifypwfile: file %s does not exist\n" \
			"$CERT_PRIVATE_DIR/$pwfile" >&2
		return 1
	elif [ "$(wc -l <"$CERT_PRIVATE_DIR/$pwfile")" != "0" ] ; then
		printf "Error: password File %s contains trailing newline\n" \
			"$CERT_PRIVATE_DIR/$pwfile" >&2
		return 1
	fi

	return 0
}

##### util-getIP #############################################################
function util-getIP {
	local url="$1"
	local ipfamily="${2:-46}"
	local resultvar="$3" # if empty print result to stdout
	local result=()
	local input=()
	local digout=""

	if [ -z "$url" ] ; then
		printf "%s: got no url (parm 1)\n" "${FUNCNAME[0]}" >&2
		return 1
	elif [[ "$ipfamily" =~ [^46] ]] ; then
		printf "%s: invalid parm 2 %s (only 46 allowed)\n" \
			"${FUNCNAME[0]}" "$ipfamily" >&2
		return 1
	fi

	if [[ "$url" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] ; then
		# url is an IPv4 address
		if [[ "$ipfamily" =~ 4 ]] ; then
			result+=( "$url" )
		else
			printf "%s: IPv4 address but IP family 4 not allowed in %s\n" \
				"${FUNCNAME[0]}" "$url" >&2
			return 1
		fi
	elif ip -6 route get "$url/128" >/dev/null 2>&1 ; then
		# trick to verify IPv6 syntax taken from https://stackoverflow.com/questions/26796769/how-to-validate-a-ipv6-address-format-with-shell
		# url is an IPv6 addrrss
		if [[ "$ipfamily" =~ 6 ]] ; then
			result+=( "$url" )
		else
			printf "%s: IPv6 address but IP family 6 not allowed in %s\n" \
				"${FUNCNAME[0]}" "$url" >&2
			return 1
		fi
	else
		digout=$(dig "$url" A) &&
		digout+=$(dig "$url" AAAA) &&
		true || return 1

		while IFS=$'\t ' read -r -a input
		do
			if [[ "${input[*]}" =~ ^\; ]] ; then
				continue
			elif [ -z "${input[*]}" ] ; then
				continue
			fi

			#DEBUG printf "dig Output: %s\n" "$(sed -n l <<<"${input[*]}")"
			if
				[[ "$ipfamily" =~ 4 ]] &&
				[ "${input[2]}" == IN ] &&
				[ "${input[3]}" == A ]
			then
				result+=( "${input[4]}" )
			fi

			if
				[[ "$ipfamily" =~ 6 ]] &&
				[ "${input[2]}" == IN ] &&
				[ "${input[3]}" == AAAA ]
			then
				result+=( "${input[4]}" )
			fi
		done <<<"$digout"

		if [ "${#result[@]}" == 0 ] ; then
			printf "%s: No DNS adress for %s\n" "${FUNCNAME[0]}" "$url" >&2
			return 1
		fi
	fi

	if [ -z "$resultvar" ] ; then
		for f in "${result[@]}" ; do
			printf "%s\n" "$f"
		done
	else
		eval "$resultvar"'=("${result[@]}")'
	fi

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

	if [ "$#" != "3" ] ; then
		printf "%s: Internal Error. Git %s parms (exp=3)\n" \
			"${FUNCNAME[0]}" "$#"
		return 1
	elif [[ "$OSTYPE" =~ darwin* ]] ; then
		# not supported on MacOS since sed on MacOS does not support
		# the q<nr> command, only q with no parm.
		printf "%s: not supported on MacOS\n" "${FUNCNAME[0]}"
		return 1
	fi

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

function util_retry {
	# parm 1: Timout in seconds
	# parm 2: sleeping time between tries in seconds
	# parm 3+: command to be executed
	if [ "$#" -lt 3 ] ; then
		printf "%s: Internal error: too few parameters (%s < 3)\n" \
			"${FUNCNAME[0]}" "$#"
		return 1
	fi

	local -r timeout="$1"
	local -r sleep="$2"
	shift 2 || return 1
	local slept=0 # beginning

	while [ "$slept" -lt "$timeout" ] ; do
		if "$@"
		then
			printf "\tOK after %s seconds\n" "$slept"
			return 0
		fi

		printf "\twaiting another %s seconds (%s/%s)\n" \
				"$sleep" "$slept" "$timeout"
		sleep "$sleep"
		(( slept += sleep ))
	done

	printf "\tTIMEOUT after %s seconds\n" \
		"$timeout"

	return 1
}

##### Main ###################################################################
# do nothing
