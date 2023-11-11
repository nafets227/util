#!/bin/bash

INSTALL_BOOT="$1"

ls "$INSTALL_BOOT" >/dev/null && # activate auto-mount
paccache -r -k 2 && # remove old packages
pacman -Suyw --noconfirm && # download updates
true || exit 1

if pacman -Qu >/dev/null ; then # updates available
	pacman -Su --noconfirm &&
	systemctl reboot &&
	true || exit 1
fi

exit 0
