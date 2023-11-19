#!/usr/bin/env bash
#
# Test util
#
# (C) 2023 Stefan Schallenberg
#

function do_test {
	testset_init

	cat >"$TESTSETDIR/testconfig1.txt" <<-EOF || return 1
		# var1=bla
		EOF
	test_exec_simple "util_updateConfig $TESTSETDIR/testconfig1.txt var1 newvalue1" &&
	test_exec_simple "cat $TESTSETDIR/testconfig1.txt" &&
		test_lastoutput_contains "# var1=bla" &&
		test_lastoutput_contains " var1=newvalue1"

	cat >"$TESTSETDIR/testconfig2.txt" <<-EOF || return 1
		# var2 = bla bla
		EOF
	test_exec_simple "util_updateConfig $TESTSETDIR/testconfig2.txt var2 newvalue2" &&
	test_exec_simple "cat $TESTSETDIR/testconfig2.txt" &&
		test_lastoutput_contains "# var2 = bla bla"
		test_lastoutput_contains " var2 = newvalue2"

	cat >"$TESTSETDIR/testconfig3.txt" <<-EOF || return 1
		var3 = value3
		EOF
	test_exec_simple "util_updateConfig $TESTSETDIR/testconfig3.txt var3 newvalue3" &&
	test_exec_simple "cat $TESTSETDIR/testconfig3.txt" &&
		test_lastoutput_contains "#var3 = value3"
		test_lastoutput_contains "var3 = newvalue3"

	local -r TAB=$'\t'
	cat >"$TESTSETDIR/testconfig4.txt" <<-EOF || return 1
		### this is a comment. note the leading tab in next line!
		${TAB}var4=value4
		EOF
	test_exec_simple "util_updateConfig $TESTSETDIR/testconfig4.txt var4 newvalue4" &&
	test_exec_simple "cat $TESTSETDIR/testconfig4.txt" &&
		test_lastoutput_contains "${TAB}#var4=value4"
		test_lastoutput_contains "${TAB}var4=newvalue4"

	cat >"$TESTSETDIR/testconfig5.txt" <<-EOF || return 1
		##### var5  =   value5
		EOF
	test_exec_simple "util_updateConfig $TESTSETDIR/testconfig5.txt var5 newvalue5" &&
	test_exec_simple "cat $TESTSETDIR/testconfig5.txt" &&
		test_lastoutput_contains "##### var5  =   value5"
		test_lastoutput_contains " var5  =   newvalue5"

	testset_summary

	return $?
}

##### Main ####################################################################
PRJDIR="$(dirname "${BASH_SOURCE[0]}")"
BASEDIR="$PRJDIR/../.."

. "$BASEDIR/util/util-functions.sh" || exit 1
. "$BASEDIR/util/test-functions.sh" || exit 1

do_test

exit $?
