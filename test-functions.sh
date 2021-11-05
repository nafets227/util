#!/bin/sh
#
# Allgemeine Test Bibliothek
#
# (C) 2017 Stefan Schallenberg

function test_cleanImap {
	if [ "$#" -ne 3 ] ; then
		printf "%s: Internal Error. Got %s parms (exp=3)\n" \
			"$FUNCNAME" "$#"
		return 1
	fi

	local mail_adr="$1"
	local mail_pw="$2"
	local mail_srv="$3"

	local imapstatus

	printf "Cleaning %s at %s. Deleting all Mails.\n" \
		"$mail_adr" "$mail_srv"

	imapstatus=$(
		curl --ssl --silent --show-error \
		"imap://$mail_srv" \
		--user "$mail_adr:$mail_pw" \
		--request 'STATUS INBOX (MESSAGES)'
	) || return 1
	imapstatus=${imapstatus%%$'\r'} # delete CR LF

	#DEBUG printf "DEBUG: Status=%s\n" "$imapstatus"
	if [ "${imapstatus:0:25}" != "* STATUS INBOX (MESSAGES " ] ; then
		printf "Wrong Status received from IMAP: \"%s\"\n" \
			"$imapstatus"
		return 1
	elif [ "$imapstatus" == "* STATUS INBOX (MESSAGES 0)" ] ; then
		# 0 Messages -> no deleting needed
		return 0
	fi

	imapstatus=$(
		curl --ssl --silent --show-error \
		"imap://$mail_srv/INBOX" \
		--user "$mail_adr:$mail_pw" \
		--request 'STORE 1:* +FLAGS \Deleted'
	) || return 1

	imapstatus=$(
		curl --ssl --silent --show-error \
		"imap://$mail_srv/INBOX" \
		--user "$mail_adr:$mail_pw" \
		--request 'EXPUNGE'
	) || return 1

	return 0
}

function test_putImap {
	if [ "$#" -ne 3 ] ; then
		printf "%s: Internal Error. Got %s parms (exp=3)\n" \
			"$FUNCNAME" "$#"
		return 1
	fi

	local mail_adr="$1"
	local mail_pw="$2"
	local mail_srv="$3"

	printf "Storing a Mail into %s at %s.\n" \
		"$mail_adr" "$mail_srv"

	cat >$TESTSETDIR/testmsg <<-EOF &&
		Return-Path: <$mail_adrt>
		From: Test-From <$mail_adr>
		Content-Type: text/plain; charset=us-ascii
		Content-Transfer-Encoding: 7bit
		Mime-Version: 1.0 (Mac OS X Mail 10.2 \(3259\))
		Subject: Test from test_putImap
		Date: Thu, 4 Mar 2017 11:50:19 +0100
		To: Test-To <$mail_adr>

		Test
		EOF

	curl --ssl --silent --show-error \
		"imap://$mail_srv/INBOX" \
		--user "$mail_adr:$mail_pw" \
		-T $TESTSETDIR/testmsg &&

	curl --ssl --silent --show-error \
		"imap://$mail_srv/INBOX" \
		--user "$mail_adr:$mail_pw" \
		--request 'STORE 1 -Flags /Seen' &&

	true || return 1

	return 0
}

function test_exec_init {
	local testdesc="$1"

	testnr=$(( ${testnr-0} + 1))
	testexecnr=$testnr

	printf "Executing Test %d (%s:%s %s) ... " "$testnr" \
		"${BASH_SOURCE[2]}" "${BASH_LINENO[1]}" "${FUNCNAME[2]}"

	if [ ! -z "$testdesc" ] ; then
		printf "\t%s\n" "$testdesc"
	fi

	return 0
}

function test_lastoutput_contains {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr
	local search="$1"
	local extension="${2-.out}"

	local grep_cnt
	grep_cnt=$(grep -z -c "$search" <$TESTSETDIR/$testexecnr$extension)
	if [ $? -ne 0 ] ; then
		# grep error
		printf "ERROR checking %s. Search: '%s'\n" \
			"$testnr" "$search"
		testsetfailed="$testsetfailed $testnr"
		return 1
	elif [ "$grep_cnt" == "0" ] ; then
		# expected text not in output.
		printf "CHECK %s FAILED. '%s' not found in output of test %s\n" \
			"$testnr" "$search" "$testexecnr"
		printf "========== Output Test %d Begin ==========\n" "$testexecnr"
		cat $TESTSETDIR/$testexecnr.out
		printf "========== Output Test %d End ==========\n" "$testexecnr"
		testsetfailed="$testsetfailed $testnr"
	else
		# expected text in output -> OK
		testsetok=$(( ${testsetok-0} + 1))
	fi

	return 0
}

# Parameters:
#     1 - command to test
#     2 - expected RC [default: 0]
#     3 - optional message to be printed if test fails
function test_exec_simple {
	test_exec_init || return 1

	local rc_exp=${2-0}

	printf "#-----\n#----- Command: %s\n#-----\n" "$1" \
		>$TESTSETDIR/$testnr.out
	eval $1 >>$TESTSETDIR/$testnr.out 2>&1
	TESTRC=$?

	if [ $TESTRC -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		printf "CMD: %s\n" "$1"
		if [ ! -z "$3" ] ; then
			printf "Info: %s\n" "$3"
		fi
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.out
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
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
	test_exec_init || return 1

	local url="$1"
	local rc_exp=${2-200}
	shift 2

	TESTRC=$(curl -s "$@" \
		-i \
		-o $TESTSETDIR/$testnr.curlout \
		-w "%{http_code}" \
		"$url")
	local rc=$?
	if [ $rc -ne 0 ] || [ "x$TESTRC" != "x$rc_exp" ] ; then
		printf "FAILED. RC=%d HTTP-Code=%s (exp=%s)\n" \
		"$rc" "$http_code" "$rc_exp"
		printf "URL: %s\n" "$url"
		printf "Options: %s\n" "$@"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.curlout
		printf "\n"
		printf "========== Output Test %d End ==========\n" "$testnr"
		[ "$rc" -ne 0 ] && TESTRC=999
		testsetfailed="$testsetfailed $testnr"
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
	local url="$1"
	local rc_exp="${2:-0}"
	shift 2

	test_exec_init "recvmail $rc_exp $url" || return 1

	local readonly MAIL_STD_OPT="-e -n -vv -Sv15-compat -Snosave -Sexpandaddr=fail,-all,+addr"
	# -SNosave is included in -d and generates error messages - so dont include it
	#MAIL_STD_OPT="-n -d -vv -Sv15-compat -Ssendwait -Sexpandaddr=fail,-all,+addr"
	local MAIL_OPT="-S 'folder=$url'"

	LC_ALL=C MAILRC=/dev/null \
		eval mail $MAIL_STD_OPT $MAIL_OPT "$@" \
		>$TESTSETDIR/$testnr.mailout \
		2>&1 \
		</dev/null
	TESTRC=$?
	if [ $TESTRC -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "test_exec_recvmail(%s,%s,%s)\n" "$rc_exp" "$url" "$@"
		printf "CMD: mail %s %s %s\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.mailout
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
	fi
}

function test_exec_sendmail {
	testnr=$(( ${testnr-0} + 1))
	testexecnr=$testnr

	local url="$1"
	local rc_exp="${2:-0}"
	local from="$3"
	local to="$4"
	shift 4
	opts="$@"

	test_exec_init "sendmail $rc_exp $url" || return 1

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
	TESTRC=$?
	if [ $TESTRC -ne $rc_exp ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "send_testmail(%s,%s,%s,%s,%s)\n" "$rc_exp" "$url" "$from" "$to" "$*"
		printf "CMD: mailx %s %s %s '%s'\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*" "$to"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat $TESTSETDIR/$testnr.mailout
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
	fi
}

function test_assert {
	testnr=$(( ${testnr-0} + 1))

	printf "Executing Assert %d (Manual %s:%s %s) ... " "$testnr" \
		"${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "${FUNCNAME[1]}"

	if [ "$1" != "0" ] ; then
		printf "FAILED: %s\n" "$2"
		TESTRC=1
		testsetfailed="$testsetfailed $testnr"
		return $TESTRC
	fi

	printf "OK\n"
	TESTRC=0
	testsetok=$(( ${testsetok-0} + 1))
	return $TESTRC
}

function test_assert_tools {
	testnr=$(( ${testnr-0} + 1))

	printf "Executing Assert %d (Tools %s) ... " "$testnr" "$*"

	for f in "$@" ; do
		if ! errmsg=$(which $f 2>&1) ; then
			printf "FAILED: Missing %s\n\t%s\n" \
				"$f" "$errmsg"
			TESTRC=1
			testsetfailed="$testsetfailed $testnr"
			return $TESTRC
		fi
	done

	printf "OK\n"
	TESTRC=0
	testsetok=$(( ${testsetok-0} + 1))
	return $TESTRC
}

function test_assert_vars {
	testnr=$(( ${testnr-0} + 1))

	printf "Executing Assert %s (Vars %s) ... " "$testnr" "$*"

	for f in "$@" ; do
		if eval "[ -z \$$f ]" ; then
			printf "FAILED: Missing %s\n" "$f"
			TESTRC=1
			testsetfailed="$testsetfailed $testnr"
			return $TESTRC
		fi
	done

	printf "OK\n"
	TESTRC=0
	testsetok=$(( ${testsetok-0} + 1))
	return $TESTRC
}

function test_assert_files {
	testnr=$(( ${testnr-0} + 1))

	printf "Executing Assert %s (Files %s) ... " "$testnr" "$*"

	for f in "$@" ; do
		if [ ! -f "$f" ] ; then
			printf "FAILED: Missing %s\n"
			TESTRC=1
			testsetfailed="$testsetfailed $testnr"
			return $TESTRC
		fi
	done

	printf "OK\n"
	TESTRC=0
	testsetok=$(( ${testsetok-0} + 1))
	return $TESTRC
}

function test_expect_files {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr

	# parm 1: directory
	# parm 2: nr of files (except . and ..)
	local testdir="$1"
	local testexpected="$2"
	local testresult
	local rc

	if [ ${testdir:0:1} != "/" ] ; then
		testdir="$TESTSETDIR/$testdir"
	fi

	testresult=$( set -o pipefail ; ls -1A $testdir 2>/dev/null | wc -l)
	rc=$?

	if [ "$rc" != 0 ] ; then
		printf "\tCHECK %s FAILED. Cannot get files in '%s'\n" \
			"$testnr" "$1"
		testsetfailed="$testsetfailed $testnr"
		return 1
	elif [ $testresult != $testexpected ] ; then
		# nr of files differ from expected
		printf "\tCHECK %s FAILED. nr of files in '%s' is %s (exp=%s)\n" \
			"$testnr" "$1" "$testresult" "$testexpected"
#		printf "========== Output Test %d Begin ==========\n" "$testexecnr"
#		cat $TESTSETDIR/$testexecnr.out
#		printf "========== Output Test %d End ==========\n" "$testexecnr"
		testsetfailed="$testsetfailed $testnr"
		return 0
	else
		printf "\tCHECK %s OK.\n" "$testnr"
		testsetok=$(( ${testsetok-0} + 1))
		return 0
	fi

	# should not reach this
	return 99
}

function test_expect_linkedfiles {
	testnr=$(( ${testnr-0} + 1 ))
	# not increasing testexecnr

	# parm 1-n: files that should be hard-linked to each other

	local fnam
	local testexpected
	local fnamexpected
	local testresult
	local rc

	for fnam in "$@" ; do
		if [ ${fnam:0:1} != "/" ] ; then
			fnam="$TESTSETDIR/$fnam"
		fi

		testresult=$(
			set -o pipefail ;
			ls -1i $fnam 2>/dev/null | cut -f 1 -d " "
			)
		rc=$?

		if [ "$rc" != 0 ] ; then
			printf "\tCHECK %s FAILED. Cannot list file '%s'\n" \
				"$testnr" "$fnam"
			testsetfailed="$testsetfailed $testnr"
			return 1
		elif [ ! -z "$testexpected" ] && [ "$testresult" != "$testexpected" ] ; then
			printf "\tCHECK %s FAILED. '%s' and '%s' have different INode\n" \
				"$testnr" "$fnam" "$fnamexpected"
			testsetfailed="$testsetfailed $testnr"
			return 1
		elif [ -z "$testexpected" ] ; then
			testexpected="$testresult"
			fnamexpected="$fnam"
		fi
	done

	printf "\tCHECK %s OK.\n" "$testnr"
	testsetok=$(( ${testsetok-0} + 1))

	return 0
}

function testset_init {
	printf "TESTS Starting.\n"
	testsetok=0
	testnr=0
	testexecnr=0
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

	TESTSETDIR=$(mktemp -d ${TMPDIR:-/tmp}/$TESTSETNAME.XXXXXXXXXX) \
		|| return 1
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

