#!/bin/bash
#
# (C) 2015-2018 Stefan Schallenberg
#

##### install_ssl_sshtrust ###################################################
function install_allow-root-pw {

 	#----- Input checks --------------------------------------------------
	if [ ! -d "$INSTALL_ROOT" ] ; then
		printf "%s: Error \$INSTALL_ROOT=%s is no directory\n" \
			"$FUNCNAME" "$INSTALL_ROOT" >&2
		return 1
	elif fgrep "nafets.de" $INSTALL_ROOT/etc/ssh/sshd_config >/dev/null ; then
		# avoid to add this configuration a second time
		printf "Setting up SSH Root Access with Password skipped.\n"
		return 0
	fi
 	
	#----- Real Work -----------------------------------------------------
	cat >>$INSTALL_ROOT/etc/ssh/sshd_config <<-"EOF"

		# SSH config modification
		# nafets.de by util/install-functions.sh
		PermitRootLogin yes
		EOF

	#----- Closing  ------------------------------------------------------
	printf "Setting up SSH Root Access with Password completed.\n"

	return 0
}

##### install_ssl_key ( ######################################################
#         name
#         [ user = root ]
#         { link ]
function install_ssl_key {

name="$1"
src="$HOME/ssl.private/$name"
target="/etc/ssl/private/$1"
user=${2:-"root"}
group=$(getent passwd $user | cut -d: -f4)
if [ ! -z $3 ]; then
    targetlink="/etc/ssl/private/$3"
else
    targetlink=""
fi

if [ $# -lt 1 ]; then
    echo "$0 install_ssl_key ERROR: Parameter Missing"
    return -1
fi
if [ ! -r $src ]; then
    echo "$0 install_ssl_key ERROR: cannot read $src"
    return -2
    fi

cp $src $target
chmod 400 $target
chown $user:$group $target

if [ -z $targetlink ]; then
    echo "Setting up SSL Key $name (User=$user) completed."
else
    if [ -L $targetlink ] || [ -e $targetlink ]; then
        rm $targetlink
    fi
    ln -s $name $targetlink
    echo "Setting up SSL Key $name (User=$user, Link=$3) completed."
fi
}

##### install_ssl_sshtrust ###################################################
function install_ssl_sshtrust {

if [ ! -f $(dirname $BASH_SOURCE)/../ssl/root_xen.id_rsa.pub ] ; then
    echo "$0 install_ssl_sshtrust ERROR: Missing $(dirname $BASH_SOURCE)/../ssl/root_xen.pub"
    return -1
fi

install -d -m 700 /root/.ssh
install -m 600 $(dirname $BASH_SOURCE)/../ssl/root_xen.id_rsa.pub /root/.ssh/
install -m 600 $(dirname $BASH_SOURCE)/../ssl/root_xen.id_rsa.pub /root/.ssh/authorized_keys

echo "Setting up SSH Trust completed."
}

##### install_ssl_sshkey (                ###################################
#####      user = root                    ###################################
#####      fname = $user_$hostname.id_rsa )###################################
function install_ssl_sshkey {
user=${1:-"root"}
fname=${2:-"${user}_${HOSTNAME}.id_rsa"}
homedir=$(getent passwd $user | cut -d: -f6)
group=$(getent passwd $user | cut -d: -f4)

if [ ! -r ~/ssl.private/$fname ]; then
    echo "$0 install_ssl_sshkey ~/ssl.private/$fname not readable"
    echo "Setting up SSH Key $fname for $user failed."
    return 1
elif [ -z $homedir ]; then
    echo "$0 install_ssl_sshkey No homedir for User $user"
    echo "Setting up SSH Key $fname for $user failed."
    return 2
else
    if [ ! -d $homedir ]; then
        mkdir -p $homedir
        chown $user:$group $homedir
    fi

    if [ ! -d $homedir/.ssh ]; then
        mkdir -p $homedir/.ssh
        chown $user:$group $homedir/.ssh
        chmod 600 $homedir/.ssh
    fi

    cp ~/ssl.private/$fname $homedir/.ssh/
    chown $user:$group $homedir/.ssh/$fname
    chmod 600 $homedir/.ssh/$fname
    ln -s $fname $homedir/.ssh/id_rsa 
fi

echo "Setting up SSH Key $fname for $user completed."
}
