#!/bin/bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### install_nfs ############################################################
function install-nfs {
$PACMAN_CMD nfs-utils

if [ ! -d /srv/nfs4 ]; then
    mkdir -p /srv/nfs4
fi

if [ ! -f /etc/exports ] || \
    ! fgrep "Standard NFS Setup in nafets.de" /etc/exports >/dev/null ; then
    cat >>/etc/exports <<-EOF
	# Standard NFS Setup in nafets.de
	# (C) 2015 Stefan Schallenberg

	/srv/nfs4 192.168.108.0/24(rw,fsid=root,no_subtree_check,crossmnt,no_root_squash)
	EOF

    echo "Modifying idmapd.conf"
    mv /etc/idmapd.conf /etc/idmapd.conf.backup
    awk -f - /etc/idmapd.conf.backup >/etc/idmapd.conf  <<-"EOF"
	BEGIN {global=0}
	/\[Gneral\]/ { global=1; print; next }
	/Domain/ { next }
	/\[/ {
	    if (global==1) {
	        print "Domain = intranet.nafets.de"
	        print ""
	        global=2
	        }
	    }
	{ print }
	EOF

    systemctl enable rpcbind.service nfs-server.service
    systemctl start rpcbind.service nfs-server.service

    echo "Setting up NFS completed."
else
    echo "Setting up NFS skipped."
fi
}

##### install_nfs_export ( <path-to-export> ) ###############################
#function install_nfs_export {
#	install_nfs_export2 "$1" "${1#/}" "$2"
#}

##### install-nfs_export ####################################################
# Parameter:
#     <Dir>        Real Directory to be exported (e.g. /data/myshare)
#     <Share-Name> Name of the share visibile to clients (e.g. myshare)
#                  NB: Can contain slashes, but be aware of side-efects
#     [options]    either ro (default) or rw or a string of options to be
#                  put as NFS options in /etc/exports
function install-nfs_export {

if [ $# -lt 2 ]; then
    echo "$0 install_nfs_export2 ERROR: Parameter Missing"
    return -1
    fi
case $3 in 
    "" | "ro" )
        exportopt="ro,no_subtree_check,nohide,no_root_squash"
        ;;
    "rw" )
        exportopt="rw,subtree_check,nohide,no_root_squash"
        ;;
    * )
        exportopt="$3"
esac


install_mount "$1" "/srv/nfs4/$2"  "none bind 0 0"

fgrep "/srv/nfs4/$2" /etc/exports >&/dev/null
if [ $? -eq 1 ]; then
    cat >>/etc/exports <<-EOF
	/srv/nfs4/$2 192.168.108.0/24($exportopt)
	EOF
    echo "Added NFS Export $2 from $1($exportopt)"
else
    echo "Skipped NFS Export $2"
fi

}

##### install_nfs_stdexports ################################################
#function install-nfs_stdexports {
#    install_nfs_export "/etc"
#    install_nfs_export "/data"
#    install_nfs_export "/home"
#}

##### install_nfs_client ####################################################
function install-nfs_client {
$PACMAN_CMD nfs-utils

systemctl start rpcbind.service nfs-client.target remote-fs.target
systemctl enable rpcbind.service nfs-client.target remote-fs.target
}
