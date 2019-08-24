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

	local http_code
	http_code=$(curl -s "$@" \
		-i \
		-o $TESTSETDIR/$testnr.curlout \
	       	-w "%{http_code}" \
		"$url")
	local rc=$?
       	if [ $rc -ne 0 ] || [ "$http_code" != "$rc_exp" ] ; then
		printf "FAILED. RC=%d HTTP-Code=%s (exp=%s)\n" \
	       		"$rc" "$http_code" "$rc_exp"
		printf "URL: %s\n" "$url"
		printf "Options: %s\n" "$@"
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

function test_exec_recvmail {
	testnr=$(( ${testnr-0} + 1))
	printf "Executing Test %d ... " "$testnr"

	local url="$1"
	local rc_exp="${2:-0}"
	shift 2

	local readonly MAIL_STD_OPT="-e -n -vv -Sv15-compat -Snosave -Sexpandaddr=fail,-all,+addr"
	# -SNosave is included in -d and generates error messages - so dont include it
	#MAIL_STD_OPT="-n -d -vv -Sv15-compat -Ssendwait -Sexpandaddr=fail,-all,+addr"
	local MAIL_OPT="-S 'folder=$url'"

	LC_ALL=C MAILRC=/dev/null \
		eval mail $MAIL_STD_OPT $MAIL_OPT "$@" \
		>$TESTSETDIR/$testnr.mailout \
		2>&1 \
		</dev/null
	rc=$?
	if [ $rc -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "test_exec_recvmail(%s,%s,%s)\n" "$rc_exp" "$url" "$@"
		printf "CMD: mail %s %s %s\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.mailout
		printf "========== Output Test %d End ==========\n" "$testnr"
	else
		printf "OK\n"
	fi
}

function test_exec_sendmail {
	testnr=$(( ${testnr-0} + 1))
	printf "Executing Test %d ... " "$testnr"

	local url="$1"
	local rc_exp="${2:-0}"
	local from="$3"
	local to="$4"
	shift 4
	opts="$@"

	local readonly MAIL_STD_OPT="-n -vv -Sv15-compat -Ssendwait -Snosave -Sexpandaddr=fail,-all,+addr"
	# -SNosave is included in -d and generates error messages - so dont include it
	#MAIL_STD_OPT="-n -d -vv -Sv15-compat -Ssendwait -Sexpandaddr=fail,-all,+addr"
	MAIL_OPT="-S 'smtp=$url'"
	MAIL_OPT="$MAIL_OPT -s 'Subject TestMail $testnr'"
	MAIL_OPT="$MAIL_OPT -r '$from'"

	LC_ALL=C MAILRC=/dev/null \
		eval mail $MAIL_STD_OPT $MAIL_OPT "$@" '$to' \
		>$TESTSETDIR/$testnr.mailout \
		2>&1 \
		<<<"Text TestMail $testnr"
	rc=$?
	if [ $rc -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "send_testmail(%s,%s,%s,%s,%s)\n" "$rc_exp" "$url" "$from" "$to" "$*"
		printf "CMD: mailx %s %s %s '%s'\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*" "$to"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.mailout
		printf "========== Output Test %d End ==========\n" "$testnr"
	else
		printf "OK\n"
	fi
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

