#!/usr/bin/env bash
#
# (C) 2015-2018 Stefan Schallenberg
# (C) 2016 Veronika Ruoff
#

##### install-timer ##########################################################
function install-timer {
	name="$1"
	script="$2"
	onBootSec="$3"
	onUnitActiveSec="$4"
	onCalendar="$5"
	user="${6:-root}"

	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"${FUNCNAME[0]}" "$INSTALL_ROOT" >&2
		return 1
	elif [ "$#" -lt 1 ] ; then
		printf "%s: Internal Error. Got %s parms (Exp=1+)\n" \
			"${FUNCNAME[0]}" "$#"
		return 1
	elif	[ -z "$onBootSec" ] && \
			[ -z "$onUnitActiveSec" ] && \
			[ -z "$onCalendar" ] ; then
		printf "%s: Internal Error. Neither parm 3,4 or 5 are set.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	#----- Real Work -----------------------------------------------------
	FNTIMER="$INSTALL_ROOT/etc/systemd/system/${name}.timer"
	cat >"$FNTIMER" <<-EOF
		# nafetsde-${name}.timer
		#
		# (C) 2016-2018 Stefan Schallenberg
		#
		[Unit]
		Description="$name Automatismen auf nafets.de (timer)"

		[Install]
		WantedBy=multi-user.target

		[Timer]
		Unit=${name}.service
		EOF
	[ -n "$onBootSec" ] &&
		printf "OnBootSec=%s\n" "$onBootSec" >>"$FNTIMER"
	[ -n "$onUnitActiveSec" ] &&
		printf "OnUnitActiveSec=%s\n" "$onUnitActiveSec" >>"$FNTIMER"
	[ -n "$onCalendar" ] &&
		printf "OnCalendar=%s\n" "$onCalendar" >>"$FNTIMER"

	FNSERVICE="$INSTALL_ROOT/etc/systemd/system/${name}.service"
	cat >"$FNSERVICE" <<-EOF
		# nafetsde-${name}.service
		#
		# (C) 2015-2018 Stefan Schallenberg
		#
		[Unit]
		Description="$name Automatismen auf nafets.de (service)"

		[Service]
		Type=simple
		ExecStart=$script
		User=$user
		EOF

	systemctl --root="$INSTALL_ROOT" enable "${name}.timer"

	#----- Closing  ------------------------------------------------------
	printf "Timer %s to call %s as %s [%s, %s, %s] uccessfully setup.\n" \
		"$name" "$script" "$user" \
		"$onBootSec" "$onUnitActiveSec" "$onCalendar"

	return 0
}
