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

##### Main ###################################################################
# do nothing

