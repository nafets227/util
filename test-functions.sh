#!/bin/bash
#
# Allgemeine Test Bibliothek
#
# (C) 2017 Stefan Schallenberg

function test_cleanImap {
	if [ "$#" -ne 3 ] ; then
		printf "%s: Internal Error. Got %s parms (exp=3)\n" \
			"${FUNCNAME[0]}" "$#"
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
			"${FUNCNAME[0]}" "$#"
		return 1
	fi

	local mail_adr="$1"
	local mail_pw="$2"
	local mail_srv="$3"

	printf "Storing a Mail into %s at %s.\n" \
		"$mail_adr" "$mail_srv"

	cat >"$TESTSETDIR/testmsg" <<-EOF &&
		Return-Path: <$mail_adr>
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
		-T "$TESTSETDIR/testmsg" &&

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

	if [ -n "$testdesc" ] ; then
		printf "\t%s\n" "$testdesc"
	fi

	return 0
}

function test_lastoutput_contains {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr
	local search="$1"
	local extension="${2:-.out}"
	local grepopts="$3"
	local altsearch="$4"

	local grep_cnt
	#shellcheck disable=SC2086 # grepopts contains multiple parms
	grep_cnt=$(grep -c $grepopts "$search" <"$TESTSETDIR/$testexecnr$extension")
	if [ $? -gt 1 ] ; then
		# grep error
		printf "ERROR checking %s. Search: '%s'\n" \
			"$testnr" "$search"
		testsetfailed="$testsetfailed $testnr"
		return 1
	elif [ "$grep_cnt" == "0" ] ; then
		# expected text not in output.
		printf "CHECK %s FAILED. '%s' not found in output of test %s\n" \
			"$testnr" "$search" "$testexecnr"
		if [ -n "$altsearch" ] ; then
			printf "========== Selected Output Test %d Begin ==========\n" "$testexecnr"
			grep "$altsearch" "$TESTSETDIR/$testexecnr$extension"
			printf "========== Selected Output Test %d End ==========\n" "$testexecnr"
		fi
		testsetfailed="$testsetfailed $testnr"
	else
		# expected text in output -> OK
		testsetok=$(( ${testsetok-0} + 1))
	fi

	return 0
}

function test_expect_lastoutput_linecount {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr
	local linecountexp="$1"
	local extension="${2:-.out}"

	local linecountact
	linecountact=$(wc -l <"$TESTSETDIR/$testexecnr$extension")
	linecountact=$(( linecountact - 4 )) # Ignore Log Lines inserted at the beginning
	if [ $? -gt 1 ] ; then
		# wc error
		printf "ERROR checking linecount %s.\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
		return 1
	elif [ "$linecountact" == "$linecountexp" ] ; then
		# line count as expected -> OK
		testsetok=$(( ${testsetok-0} + 1))
	else
		# linecount not as expected
		printf "CHECK %s FAILED. Linecountof test %s is %d (exp=%d)\n" \
			"$testnr" "$testexecnr" "$linecountact" "$linecountexp"
		printf "========== Output Test %d Begin ==========\n" "$testexecnr"
		cat "$TESTSETDIR/$testexecnr$extension"
		printf "========== Output Test %d End ==========\n" "$testexecnr"
		testsetfailed="$testsetfailed $testnr"
	fi

	return 0
}

function test_get_lastoutput {
	local extension="${2:-.out}"

	tail --lines=+5 "$TESTSETDIR/$testexecnr$extension" || return 1

	return 0
}

function test_get_ipv6prefix {
	local prefix

	while IFS= read -r line
	do
		adr=$( sed -n 's/^.*inet6 \([0-9a-fA-F:]*\).*$/\1/p' <<<"$line") || return 1

		if [[ $adr =~ ^[23].* ]] ; then
			prefix="$(sed -n 's/^\([0-9a-fA-F]\{1,4\}:[0-9a-fA-F]\{1,4\}:[0-9a-fA-F]\{1,4\}:[0-9a-fA-F]\{1,4\}\).*$/\1/p' <<<"$adr")"
			break
		fi
	done <<< "$($TEST_IP6CFG)"

	if [ -z "$prefix" ] ; then
		printf "Could not determine public IPv6 prefix\n" >&2
		return 1
	fi

	printf "%s" "$prefix"

	return 0
}

function test_wait_kubepods {
	# Parameters:
	#     1 - Kubernetes Labels to identify relevant pods
	#     2 - timeout in seconds [default=60]
	if [ "$#" -lt 1 ] ; then
		printf "%s: Internal error: too few parameters (%s < 1)\n" \
			"${BASH_FUNC[0]}" "$#"
		return 1
	fi
	local -r podlabels="$1"
	local -r timeout=${2:-60}

	if ! kubectl --kubeconfig "$KUBE_CONFIGFILE" \
		wait pods \
		--namespace "$KUBE_NAMESPACE" \
		--timeout="${timeout}s" \
		--for=condition=Ready \
		-l "$podlabels"
	then
		kubectl --kubeconfig "$KUBE_CONFIGFILE" \
			get pods \
			--namespace "$KUBE_NAMESPACE" \
			-l "$podlabels"
		kubectl --kubeconfig "$KUBE_CONFIGFILE" \
			logs \
			--namespace "$KUBE_NAMESPACE" \
			-l "$podlabels"
		return 1
	fi

	return 0
}

function test_exec_cmd {
	# Parameters:
	#     1 - expected RC [default: 0]
	#     2 - optional message to be printed if test fails
	#     3+ - command to be executed
	if [ "$#" -lt 3 ] ; then
		printf "%s: Internal error: too few parameters (%s < 3)\n" \
			"${BASH_FUNC[0]}" "$#"
		return 1
	fi

	test_exec_init || return 1

	local -r rc_exp=${1:-0}
	local testmsg=$2
	shift 2 || return 1

	printf "#-----\n#----- Command: %s\n#-----\n" "$@" \
		>"$TESTSETDIR/$testnr.out"
	"$@" >>"$TESTSETDIR/$testnr.out" 2>&1
	TESTRC=$?

	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		printf "CMD: %s\n" "$@"
		if [ -n "$testmsg" ] ; then
			printf "Info: %s\n" "$testmsg"
		fi
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.out"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "CMD: %s\n" "$@"
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat "$TESTSETDIR/$testnr.out"
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function test_exec_simple {
	# DEPRECATED. Use test_exec_cmd instead.
	# Parameters:
	#     1 - command to test
	#     2 - expected RC [default: 0]
	#     3 - optional message to be printed if test fails

	test_exec_cmd "$2" "$3" eval "$1"

	return $?
}

function test_exec_ssh {
	# Parameters:
	#     1 - machine name to ssh to
	#     2 - expected RC [default: 0]
	#     3ff - command to test
	test_exec_init || return 1

	local sshtarget="$1"
	shift
	local rc_exp=${1:-0}
	shift

	local sshopt="-n"

	printf "#-----\n#----- SSH Machine: %s\n#----- Command: %s\n#-----\n" \
		"$sshtarget" "$*" \
		>"$TESTSETDIR/$testnr.out"
	[ "$#" == 0 ] && sshopt=""
	#shellcheck disable=SC2029
	ssh $sshopt "$sshtarget" "$*" >>"$TESTSETDIR/$testnr.out" 2>&1
	TESTRC=$?

	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		printf "SSH %s CMD: %s\n" "$sshtarget" "$*"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.out"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "SSH %s CMD: %s\n" "$sshtarget" "$*"
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat "$TESTSETDIR/$testnr.out"
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
	local http_code=""

	TESTRC=$(curl -s "$@" \
		-i \
		-o "$TESTSETDIR/$testnr.curlout" \
		-w "%{http_code}" \
		"$url")
	local rc=$?
	if [ $rc -ne 0 ] || [ "x$TESTRC" != "x$rc_exp" ] ; then
		printf "FAILED. RC=%d HTTP-Code=%s (exp=%s)\n" \
		"$rc" "$http_code" "$rc_exp"
		printf "URL: %s\n" "$url"
		printf "Options: %s\n" "$@"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.curlout"
		printf "\n"
		printf "========== Output Test %d End ==========\n" "$testnr"
		[ "$rc" -ne 0 ] && TESTRC=999
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat "$TESTSETDIR/$testnr.curlout"
			printf "\n"
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function test_internal_exec_kube {
	local -r kubecmd="$1"
	local -r kubecomment="$2"
	local -r kubenolog="$3"
	local cmd rc

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	cmd="kubectl"
	cmd+=" --kubeconfig $KUBE_CONFIGFILE"
	cmd+=" --namespace $KUBE_NAMESPACE"

	if [ -n "$kubecomment" ] ; then
		printf "#----- %s\n" \
			"$kubecomment" \
			>>"$TESTSETDIR/$testnr.out"
	fi

	if [ -z "$kubenolog" ] ; then
		printf "#----- Command: %s\n" \
			"$cmd $kubecmd" \
			>>"$TESTSETDIR/$testnr.out"
	fi

	#shellcheck disable=SC2086 # cmd and kubecmd contains more than one parm
	TEST_INTERNAL_EXEC_KUBE_OUTPUT=$(set +x ; eval $cmd $kubecmd 2>&1)
	rc=$?
	if [ -z "$kubenolog" ] || [ "$rc" != 0 ] ; then
		printf "%s\n" \
			"$TEST_INTERNAL_EXEC_KUBE_OUTPUT" \
			>>"$TESTSETDIR/$testnr.out"
	fi

	return $rc
}

function test_exec_kubecron {
	# Parameters:
	#     1 - name of the cronjob
	#     2 - expected RC [default: 0], possible values:
	#         0 - OK
	#         1 - Job did run, but with error
	#         2 - Job timed out
	#         3 - Job could not be run (Kubernetes error when creating and scheduling)
	#     3 - optional message to be printed if test fails
	#     4 - Timeout in seconds [optional, default=240]
	test_assert_tools "jq" || return 1
	test_exec_init || return 1

	local -r cronjobname="$1"
	local -r rc_exp="${2-0}"
	local -r infomsg="$3"
	local -r sleepMax=${4:-240}
	local -r sleepNext=5

	local STATUS ACTIVE FAILED SUCCEEDED CONDSTATUS
	local slept=0

	TESTRC=

	test_internal_exec_kube \
		"delete job/$cronjobname-test" \
		"try deleting previous jobs"
	# Ignore errors here!

	test_internal_exec_kube \
		"create job $cronjobname-test --from=cronjob/$cronjobname" \
		|| TESTRC=3

	while [ -z "$TESTRC" ] ; do
		test_internal_exec_kube \
			"get job $cronjobname-test -o json | jq '.status'" \
			"" "1" &&
		STATUS="$TEST_INTERNAL_EXEC_KUBE_OUTPUT" &&
		ACTIVE=$(jq '.active // 0' <<<"$STATUS" 2>&1) &&
		FAILED=$(jq '.failed // 0' <<<"$STATUS" 2>&1) &&
		SUCCEEDED=$(jq '.succeeded // 0' <<<"$STATUS" 2>&1) &&
		CONDSTATUS=$(jq -r 'try .conditions[] | select(.status=="True").type' <<<"$STATUS" 2>&1)
		#shellcheck disable=SC2181 # using $? here helps to keep the structure
		if [ "$?" != 0 ] ; then
			printf "%s\nACTIVE=%s\nFAILED=%s\nSUCCEEDED=%s\nCONDSTATUS=%s\n" \
				"$STATUS" "$ACTIVE" "$FAILED" "$SUCCEEDED" "$CONDSTATUS" \
				>>"$TESTSETDIR/$testnr.out"
			TESTRC=3
			break
		elif [ "$CONDSTATUS" == "Complete" ] ; then
			printf "  Completed Job: %s/%s/%s/%s (active/failed/succeeded/condition)\n" \
				"$ACTIVE" "$FAILED" "$SUCCEEDED" "$CONDSTATUS" \
				>>"$TESTSETDIR/$testnr.out"
			TESTRC=0
			break
		elif [ "$CONDSTATUS" == "Failed" ] ; then
			printf "     Failed Job: %s/%s/%s/%s (active/failed/succeeded/condition)\n" \
				"$ACTIVE" "$FAILED" "$SUCCEEDED" "$CONDSTATUS" \
				>>"$TESTSETDIR/$testnr.out"
			TESTRC=1
			break
		elif [ "$slept" -gt "$sleepMax" ] ; then
			printf "   TimedOut Job: %s/%s/%s/%s (active/failed/succeeded/condition)\n" \
				"$ACTIVE" "$FAILED" "$SUCCEEDED" "$CONDSTATUS" \
				>>"$TESTSETDIR/$testnr.out"
			TESTRC=2
			break
		else
			printf "Waiting for Job: %s/%s/%s/%s (active/failed/succeeded/condition)" \
				"$ACTIVE" "$FAILED" "$SUCCEEDED" "$CONDSTATUS" \
				>>"$TESTSETDIR/$testnr.out"
			printf " sleep %s seconds (%s/%s)\n" \
					"$sleepNext" "$slept" "$sleepMax" \
					>>"$TESTSETDIR/$testnr.out"

			sleep $sleepNext ; slept=$(( slept + sleepNext ))
		fi
	done

	# Always try to print logs of Pods, even in case of errors
	test_internal_exec_kube \
		"logs job/$cronjobname-test --all-containers" \
		|| TESTRC=2

	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		if [ -n "$infomsg" ] ; then
			printf "Info: %s\n" "$infomsg"
		fi
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.out"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		cmd="kubectl --kubeconfig $KUBE_CONFIGFILE --namespace $KUBE_NAMESPACE"
		cmd+=" delete job/$cronjobname-test"
		printf "#----- Delete Job\n#----- Command: %s\n" "$cmd" \
			>>"$TESTSETDIR/$testnr.out"
		#shellcheck disable=SC2086 # cmd contains multiple parms
		eval $cmd >>"$TESTSETDIR/$testnr.out" 2>&1 # ignore if deleting job fails.

		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat "$TESTSETDIR/$testnr.out"
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function test_exec_kubenode {
	# Parameters:
	#     1 - name of the node
	#     2 - expected RC [default: 0]
	#     3 - optional message to be printed if test fails
	#     4+ - IP adresses or DNS names to verify connection with
	local -r nodename="$1"
	local -r rc_exp="$2"
	local -r msg="$3"
	shift 3

	test_exec_kubenode2 "$nodename" "$nodename" "$rc_exp" "$msg" "$@"
}

function test_exec_kubenode2 {
	# Parameters:
	#     1 - name of the node
	#     2 - DNS name of the VM to run kubectl
	#         if empty, the current machine will be used (no ssh)
	#     3 - expected RC [default: 0]
	#     4 - optional message to be printed if test fails
	#     5+ - IP adresses or DNS names to verify connection with
	local -r nodename="$1"
	local -r dnsname="$2"
	local -r rc_exp="$3"
	local -r msg="$4"
	shift 4
	test_exec_kubenode3 "$nodename" "$dnsname" "" "$rc_exp" "$msg" "$@"
}

function test_exec_kubenode3 {
	# Parameters:
	#     1 - name of the node
	#     2 - DNS name of the VM to run kubectl
	#         if empty, the current machine will be used (no ssh)
	#     3 - timeout in sec [default: 3]
	#     4 - expected RC [default: 0]
	#     5 - optional message to be printed if test fails
	#     5+ - IP adresses or DNS names to verify connection with
	test_exec_init || return 1

	local -r nodename="${1,,}" # lowercase
	local -r dnsname="$2"
	local -r timeout="${3:-3}"
	local -r rc_exp="${4:-0}"
	local -r msg="$5"
	shift 4

	if [ -z "$nodename" ] ; then
		printf "Error: nodename empty\n"
		return 1
	elif [ -z "$*" ] ; then
		printf "Error: Parm IP Adress missing\n"
		return 1
	fi

	local bashcmd
	bashcmd=""
	bashcmd+=" set -x"
	bashcmd+=";i=\$(date '+%s')"
	bashcmd+=";while (( \$(date '+%s') - i \< $timeout )) ; do true "
	for f in "$@" ; do
		bashcmd+=" && ping -c 1 -4 $f"
		bashcmd+=" && ping -c 1 -6 $f"
	done
	bashcmd+=" && break"
	bashcmd+="; sleep 1 ; done"

	local kubecmd
	kubecmd=""
	kubecmd+="run kubenodetest"
	kubecmd+=" --image alpine:latest"
	kubecmd+=" --restart=Never"
	kubecmd+=" --overrides='{ \"apiVersion\": \"v1\", \"spec\": { \"nodeName\": \"$nodename\" } }'"
	kubecmd+=" --stdin"
	kubecmd+=" --rm"
	kubecmd+=" --pod-running-timeout=3m"

	if [ -n "$dnsname" ] ; then
		ssh -n -o StrictHostKeyChecking=no "$dnsname" \
			"kubectl $kubecmd <<<\"$bashcmd\"" >>"$TESTSETDIR/$testnr.out" 2>&1
		TESTRC=$?
	else
		#shellcheck disable=SC2086 # kubecmd contains multiple parms
		kubectl $kubecmd <<<"$bashcmd" >>"$TESTSETDIR/$testnr.out" 2>&1
		TESTRC=$?
	fi

	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		if [ -n "$msg" ] ; then
			printf "Info: %s\n" "$3"
		fi
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.out"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
		if [ "$TESTSETLOG" == "1" ] ; then
			printf "========== Output Test %d Begin ==========\n" "$testnr"
			cat "$TESTSETDIR/$testnr.out"
			printf "========== Output Test %d End ==========\n" "$testnr"
		fi
	fi

	return 0
}

function test_exec_recvmail {
	local url="$1"
	local rc_exp="${2:-0}"
	shift 2

	[ -z "$TEST_SNAIL" ] && return 1
	test_exec_init "recvmail $rc_exp $url" || return 1

	local -r MAIL_STD_OPT="-e -n -vv -Sv15-compat -Snosave -Sexpandaddr=fail,-all,+addr"
	# -SNosave is included in -d and generates error messages - so dont include it
	#MAIL_STD_OPT="-n -d -vv -Sv15-compat -Ssendwait -Sexpandaddr=fail,-all,+addr"
	local MAIL_OPT="-S 'folder=$url'"

	#shellcheck disable=SC2086 # vars contain multiple parms
	LC_ALL=C MAILRC=/dev/null \
		eval $TEST_SNAIL $MAIL_STD_OPT $MAIL_OPT "$*" \
		>"$TESTSETDIR/$testnr.mailout" \
		2>&1 \
		</dev/null
	TESTRC=$?
	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$TESTRC" "$rc_exp"
		printf "test_exec_recvmail(%s,%s,%s)\n" "$url" "$rc_exp" "$@"
		printf "CMD: $TEST_SNAIL %s %s %s\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.mailout"
		printf "========== Output Test %d End ==========\n" "$testnr"
		testsetfailed="$testsetfailed $testnr"
	else
		printf "OK\n"
		testsetok=$(( ${testsetok-0} + 1))
	fi
}

function test_exec_sendmail {
	local url="$1"
	local rc_exp="${2:-0}"
	local from="$3"
	local to="$4"
	shift 4

	[ -z "$TEST_SNAIL" ] && return 1
	test_exec_init "sendmail $rc_exp $url" || return 1

	local -r MAIL_STD_OPT="-n -vv -Sv15-compat -Ssendwait -Snosave -Sexpandaddr=fail,-all,+addr"
	# -SNosave is included in -d and generates error messages - so dont include it
	#MAIL_STD_OPT="-n -d -vv -Sv15-compat -Ssendwait -Sexpandaddr=fail,-all,+addr"
	MAIL_OPT="-S 'smtp=$url'"
	MAIL_OPT="$MAIL_OPT -s 'Subject TestMail $testnr'"
	MAIL_OPT="$MAIL_OPT -r '$from'"

	#shellcheck disable=SC2086 # vars contain multiple parms
	LC_ALL=C MAILRC=/dev/null \
		eval $TEST_SNAIL $MAIL_STD_OPT $MAIL_OPT "$*" '$to' \
		>"$TESTSETDIR/$testnr.mailout" \
		2>&1 \
		<<<"Text TestMail $testnr"
	TESTRC=$?
	if [ "$TESTRC" -ne "$rc_exp" ] ; then
		printf "FAILED. RC=%d (exp=%d)\n" "$rc" "$rc_exp"
		printf "send_testmail(%s,%s,%s,%s,%s)\n" "$rc_exp" "$url" "$from" "$to" "$*"
		printf "CMD: $TEST_SNAIL %s %s %s '%s'\n" "$MAIL_STD_OPT" "$MAIL_OPT" "$*" "$to"
		printf "========== Output Test %d Begin ==========\n" "$testnr"
		cat "$TESTSETDIR/$testnr.mailout"
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
		if ! errmsg=$(which "$f" 2>&1) ; then
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

function test_expect_value {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr

	# parm 1: file
	local testvalue="$1"
	local testvalexpected="$2"
	local rc

	if [ "$testvalue" == "$testvalexpected" ] ; then
		printf "\tCHECK %s OK.\n" "$testnr"
		testsetok=$(( ${testsetok-0} + 1))
		return 0
	else
		printf "\tCHECK %s FAILED. Value='%s' (exp='%s')\n" \
			"$testnr" "$testvalue" "$testvalexpected"
		testsetfailed="$testsetfailed $testnr"
		return 0
	fi

	# should not reach this
	#shellcheck disable=SC2317
	return 99
}

function test_expect_file_missing {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr

	# parm 1: file
	local testfile="$1"
	local rc

	if [ "${testfile:0:1}" != "/" ] ; then
		testfile="$TESTSETDIR/$testfile"
	fi

	testresult=$(ls -1A "$testfile" 2>/dev/null )
	rc=$?

	if [ "$rc" == "1" ] || [ "$rc" == "2" ]; then
		printf "\tCHECK %s OK.\n" "$testnr"
		testsetok=$(( ${testsetok-0} + 1))
		return 0
	elif [ "$rc" == "0" ] ; then
		printf "\tCHECK %s FAILED. File '%s' exists\n" \
			"$testnr" "$1"
		testsetfailed="$testsetfailed $testnr"
		return 0
	else
		printf "\tCHECK %s FAILED. Cannot get files in '%s'\n" \
			"$testnr" "$1"
		testsetfailed="$testsetfailed $testnr"
		return 1
	fi

	# should not reach this
	#shellcheck disable=SC2317
	return 99
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

	if [ "${testdir:0:1}" != "/" ] ; then
		testdir="$TESTSETDIR/$testdir"
	fi

	#shellcheck disable=SC2012 # no worries about non-alpha filenames here
	testresult=$( set -o pipefail ; ls -1A "$testdir" 2>/dev/null | wc -l)
	rc=$?

	if [ "$rc" != 0 ] ; then
		printf "\tCHECK %s FAILED. Cannot get files in '%s'\n" \
			"$testnr" "$1"
		testsetfailed="$testsetfailed $testnr"
		return 1
	elif [ "$testresult" != "$testexpected" ] ; then
		# nr of files differ from expected
		printf "\tCHECK %s FAILED. nr of files in '%s' is %s (exp=%s)\n" \
			"$testnr" "$1" "$testresult" "$testexpected"
		# printf "========== Output Test %d Begin ==========\n" "$testexecnr"
		# cat $TESTSETDIR/$testexecnr.out
		# printf "========== Output Test %d End ==========\n" "$testexecnr"
		testsetfailed="$testsetfailed $testnr"
		return 0
	else
		printf "\tCHECK %s OK.\n" "$testnr"
		testsetok=$(( ${testsetok-0} + 1))
		return 0
	fi

	# should not reach this
	#shellcheck disable=SC2317
	return 99
}

function test_expect_file_contains {
	testnr=$(( ${testnr-0} + 1))
	# not increasing testexecnr

	# parm 1: file
	# parm 2: text to search for
	local testfile="$1"
	local testexpected="$2"
	local testresult
	local rc

	if [ "${testfile:0:1}" != "/" ] ; then
		testfile="$TESTSETDIR/$testfile"
	fi

	testresult=$(grep -F "$testexpected" "$testfile")
	rc=$?

	if [ "$rc" != 0 ] ; then
		printf "\tCHECK %s FAILED. %s does not contain '%s'\n" \
			"$testnr" "$1" "$2"
		testsetfailed="$testsetfailed $testnr"
		return 1
	else
		printf "\tCHECK %s OK.\n" "$testnr"
		testsetok=$(( ${testsetok-0} + 1))
		return 0
	fi

	# should not reach this
	#shellcheck disable=SC2317
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
		if [ "${fnam:0:1}" != "/" ] ; then
			fnam="$TESTSETDIR/$fnam"
		fi

		testresult=$(
			set -o pipefail ;
			#shellcheck disable=SC2012 # no worries about non-alpha filenames here
			ls -1i "$fnam" 2>/dev/null | cut -f 1 -d " "
			)
		rc=$?

		if [ "$rc" != 0 ] ; then
			printf "\tCHECK %s FAILED. Cannot list file '%s'\n" \
				"$testnr" "$fnam"
			testsetfailed="$testsetfailed $testnr"
			return 1
		elif [ -n "$testexpected" ] && [ "$testresult" != "$testexpected" ] ; then
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

	if [[ "$OSTYPE" =~ darwin* ]] ; then
		printf "Activating MacOS workaround.\n"
		# TEST_RSYNCOPT="--rsync-path=/usr/local/bin/rsync"
		TEST_SNAIL=/usr/local/bin/s-nail
		TEST_IP6CFG=ifconfig
	elif [ "$(awk -F= '/^NAME/{print $2}' /etc/os-release)" == "\"Ubuntu\"" ] ; then
		printf "Activating Ubuntu settings.\n"
		# TEST_RSYNCOPT=""
		TEST_SNAIL=s-nail
		TEST_IP6CFG="ip -6 -oneline address show"
	else
		printf "Using default OS (OSTYPE=%s, os-release/NAME=%s\n" \
			"$OSTYPE" \
			"$(awk -F= '/^NAME/{print $2}' /etc/os-release)"
		# TEST_RSYNCOPT=""
		TEST_SNAIL="mailx"
		TEST_IP6CFG="ip -6 -oneline address show"
	fi

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

	TESTSETDIR=$(mktemp -d "${TMPDIR:-/tmp}/$TESTSETNAME.XXXXXXXXXX") \
		|| return 1
	printf "\tTESTSETDIR=%s\n" "$TESTSETDIR"
	printf "\tTESTSETLOG=%s\n" "$TESTSETLOG"
	printf "\tTESTSETPARM=%s\n" "$TESTSETPARM"

	#shellcheck disable=SC2086
	set -- $TESTSETPARM

	return 0
}

function testset_success {
	if [ "$testsetok" -ne "$testnr" ] ; then
		return 1
	else
		return 0
	fi
}

function testset_summary {
	printf "TESTS Ended. %d of %d successful.\n" "$testsetok" "$testnr"
	if [ "$testsetok" -ne "$testnr" ] ; then
		printf "Failed tests:%s\n" "$testsetfailed"
		return 1
	fi

	return 0
}

