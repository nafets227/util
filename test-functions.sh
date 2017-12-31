#!/bin/sh
#
# Allgemeine Test Bibliothek
#
# (C) 2017 Stefan Schallenberg

# Parameters:
#     1 - command to test
#     2 - expected RC [default: 0]
function test_exec_simple {
	testnr=$(( ${testnr-0} + 1))
	printf "Executing Test %d ... " "$testnr"

	local rc_exp=${2-0}

	$1 >$TESTSETDIR/$testnr.out 2>&1
	local rc=$?
	
	if [ $rc -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "CMD: %s\n" "$1"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.out
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "CMD: %s\n" "$1"
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat $TESTSETDIR/$testnr.out
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function test_exec_url {
	testnr=$(( ${testnr-0} + 1))
	printf "Executing Test %d ... " "$testnr"
	
	local url="$1"
	local rc_exp=${2-200}
	shift 2
	local curl_parms="$*"

	local http_code=$(curl -s $curl_parms \
		-i \
		-o $TESTSETDIR/$testnr.curlout \
	       	-w "%{http_code}" \
		"$url")
	local rc=$?
       	if [ $rc -ne 0 ] || [ "$http_code" != "$rc_exp" ] ; then
		printf "FAILED. RC=%d HTTP-Code=%s (exp=%s)\n" \
	       		"$rc" "$http_code" "$rc_exp"
		printf "URL: %s\n" "$url"
		printf "Options: %s\n" "$curl_parms"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.curlout
		printf "\n"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat $TESTSETDIR/$testnr.curlout
			printf "\n"
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function testset_init {
	printf "TESTS Starting.\n"
	testsetok=0
	testnr=0
	testsetfailed=""

	TESTSETLOG=0
	TESTSETNAME="TestSet"
	while [ "$#" -ne 0 ] ; do case "$1" in
		--log )
			TESTSETLOG=1
			;;
		--testsetname=* )
			TESTSETNAME="${1##--testsetname=}"
			;;
		* )
			TESTSETPARM+="$1"
			;;
		esac
		shift
	done

	TESTSETDIR=$(mktemp --tmpdir --directory $TESTSETNAME.XXXXXXXXXX)
	printf "\tTESTSETDIR=%s\n" "$TESTSETDIR"
	printf "\tTESTSETLOG=%s\n" "$TESTSETLOG"
	printf "\tTESTSETPARM=%s\n" "$TESTSETPARM"

	set -- $TESTSETPARM

	return 0
}

function testset_summary {
	printf "TESTS Ended. %d of %d successful.\n" "$testsetok" "$testnr"
	if [ "$testsetok" -ne "$testnr" ] ; then
		printf "Failed tests:%s\n" "$testsetfailed"
		return 1
	fi

	return 0
}

