#!/bin/bash
#
# cert-functions.sh
#
# Functions for handling certificated in intranet
#
# (C) 2019 Stefan Schallenberg
#

readonly CERT_PRIVATE_DIR=/data/ca/private
readonly CERT_STORE_DIR=/data/ca/store
readonly CERT_ARCHIVE_DIR=/data/ca/archive

#### cert_create_key #########################################################
function cert_create_key {
	# Create a Key; fails if it already exists
	# Parameters:
	#    1 - name of the key
	# Output:
        #    $CERT_PRIVATE_DIR/$certname.key.insecure
	local name="$1"

	if [ -z "$name" ] ; then
		printf "Internal Error (%s): No parm, expected 1\n" "$BASH_FUNC"
		return 1
	elif [ -f "$CERT_PRIVATE_DIR/$name.key" ] ; then
		printf "Internal Error (%s): cert key %s already exists.\n" \
			"$BASH_FUNC" \
			"$CERT_PRIVATE_DIR/$name.key"
		return 1
	elif [ -f "$CERT_PRIVATE_DIR/$name.key.insecure" ] ; then
		printf "Internal Error (%s): cert key %s already exists.\n" \
			"$BASH_FUNC" \
			"$CERT_PRIVATE_DIR/$name.key.insecure"
		return 1
	fi

	local readonly CERT_DUMMY_PW="UmcGZUu5AX2ettn2" &&
	openssl genrsa \
		-des3 \
		-passout pass:$CERT_DUMMY_PW \
		-out $CERT_PRIVATE_DIR/$name.key \
		4096 &&
	openssl rsa \
		-passin pass:$CERT_DUMMY_PW \
		-in $CERT_PRIVATE_DIR/$name.key \
		-out $CERT_PRIVATE_DIR/$name.key.insecure \
	|| return 1

	return 0
}

##### cert_get_key ###########################################################
function cert_get_key {
	# Create a Key if it does not exist yet. Return pathname of key
	# Parameters:
	#    1 - name of the key
	# Output:
        #    $CERT_PRIVATE_DIR/$certname.key.insecure

	local name="$1"

	if [ -z "$name" ] ; then
		printf "Internal Error (%s): No parm, expected 1\n" "$BASH_FUNC" >&2
		return 1
	fi

	if [ -f "$CERT_PRIVATE_DIR/$name.key" ] &&
	   [ -f "$CERT_PRIVATE_DIR/$name.key.insecure" ] ; then
		printf "%s\n" "$CERT_PRIVATE_DIR/$name.key.insecure"
	else
		cert_create_key "$name" >&2 || return 1
		printf "%s\n" "$CERT_PRIVATE_DIR/$name.key.insecure"
	fi

	return 0
}

##### cert_create_ca #########################################################
function cert_create_ca {
	# @TODO to be implemented


	## CA erzeugen
	#openssl genrsa -des3 -out ca.key 4096
	#openssl req -new -x509 -days 365 -key ca.key -out ca.crt

	return 1
}

##### cert_query_ca ##########################################################
function cert_query_ca {
	# Parameters:
	#    1 - name of the CA (default: nafetsde-ca)
	# Prerequisites:
	#    $CERT_STORE_DIR/<caname>.crt
	#        our CA and its key
	# Output:
	#    $CERT_STORE_DIR/<caname>.crt
	#        the location of the ca

	local caname="${1:-"nafetsde-ca"}"

	if [ ! -f "$CERT_STORE_DIR/$caname.crt" ] ; then
		printf "Internal Error (%s): ca cert %s does not exist.\n" \
			"$BASH_FUNC" \
			"$CERT_STORE_DIR/$caname.crt"
		return 1
	fi

	printf "%s\n" "$CERT_STORE_DIR/$caname.crt"

	return 0
}

##### cert_create_cert #######################################################
function cert_create_cert {
	# Parameters:
	#    1 - name of certificate (without extension)
	#    2 - name of the CA (default: nafetsde-ca)
	#    3 - serial (default:1)
	#    4 - reqtxt file (default: "-" means read from stdin)
	# Prerequisites:
	#    $CERT_PRIVATE_DIR/<caname>.key
	#    $CERT_STORE_DIR/<caname>.crt
	#        our CA and its key
	#    $CERT_PRIVATE_DIR/$certname.key.insecure
	#        contains a valid private key.
	#
	# Output:
	#    $CERT_STORE_DIR/$certname.crt
	#        the certificate (without root cert)
	#    $CERT_STORE_DIR/$certname.fullchain.crt
	#        the certificate (including root cert)
	#    $CERT_STORE_DIR/$certname.reqtxt
	#        the request config given by parm #3 or default.

	local name="$1"
	local caname="${2:-"nafetsde-ca"}"
	local serial="${3:-"1"}"
	local req="${4:-"-"}"

	if [ -z "$name" ] ; then
		printf "Internal Error (%s): No parm, expected >= 1\n" "$BASH_FUNC"
		return 1
	elif [ "$req" != "-" ] && [ ! -f "$req" ] ; then
		printf "Internal Error (%s): req %s is not - and does not exist.\n" \
			"$BASH_FUNC" \
			"$req"
		return 1
	elif [ ! -f "$CERT_PRIVATE_DIR/$name.key.insecure" ] ; then
		printf "Internal Error (%s): cert key %s does not exist.\n" \
			"$BASH_FUNC" \
			"$CERT_PRIVATE_DIR/$name.key.insecure"
		return 1
	elif [ ! -f "$CERT_PRIVATE_DIR/$caname.key" ] ; then
		printf "Internal Error (%s): ca key %s does not exist.\n" \
			"$BASH_FUNC" \
			"$CERT_PRIVATE_DIR/$caname.key"
		return 1
	elif [ ! -f "$CERT_STORE_DIR/$caname.crt" ] ; then
		printf "Internal Error (%s): ca cert %s does not exist.\n" \
			"$BASH_FUNC" \
			"$CERT_STORE_DIR/$caname.crt"
		return 1
	elif [ -f "$CERT_STORE_DIR/$name.crt" ] ; then
		printf "Internal Error (%s): cert %s already exists.\n" \
			"$BASH_FUNC" \
			"$CERT_STORE_DIR/$name.crt"
		return 1
	fi

	if [ "$req" == "-" ] ; then
		# store stdin to reqtxt file
		cat >$CERT_STORE_DIR/$name.reqtxt || return 1
	else
		cp -a $req $CERT_STORE_DIR/$name.reqtxt || return 1
	fi

	openssl req \
		-new \
		-key $CERT_PRIVATE_DIR/$name.key.insecure \
		-config $CERT_STORE_DIR/$name.reqtxt \
		-out $CERT_STORE_DIR/$name.csr &&
	openssl x509 \
		-req \
		-days 365 \
		-in $CERT_STORE_DIR/$name.csr \
		-CA $CERT_STORE_DIR/$caname.crt \
		-CAkey $CERT_PRIVATE_DIR/$caname.key \
		-set_serial $serial \
		-out $CERT_STORE_DIR/$name.crt \
		-extensions v3_req \
		-extfile $CERT_STORE_DIR/$name.reqtxt &&
	cat \
		$CERT_STORE_DIR/$name.crt \
		$CERT_STORE_DIR/$caname.crt \
		>$CERT_STORE_DIR/$name.fullchain.crt \
	|| return 1

	return 0
}

##### cert_update_cert ######################################################
function cert_update_cert {
	# Parameters:
	#    1 - name of certificate (without extension)
	#    2 - name of the CA (default: nafetsde-ca)
	#    3 - reqtxt file (default: "-" means read from stdin)
	# Prerequisites:
	#    $CERT_PRIVATE_DIR/<caname>.key
	#    $CERT_STORE_DIR/<caname>.crt
	#        our CA and its key
	#    $CERT_PRIVATE_DIR/$certname.key.insecure
	#        contains a valid private key.
	#    $CERT_STORE_DIR/$certname.crt
	#        the old certificate (wused to read serial and increase it)
	#
	# Output:
	#    $CERT_STORE_DIR/$certname.crt
	#        the updated certificate (without root cert)
	#    $CERT_STORE_DIR/$certname.fullchain.crt
	#        the updated certificate (including root cert)

	local name="$1"
	local caname="${2:-"nafetsde-ca"}"
	local req="$3" # default handled in called function cert_create_cert

	if [ -z "$name" ] ; then
		printf "Internal Error (%s): No parm, expected >= 1\n" "$BASH_FUNC"
		return 1
	elif [ ! -f "$CERT_STORE_DIR/$name.crt" ] ; then
		printf "Internal Error (%s): cert %s does not exist.\n" \
			"$BASH_FUNC" \
			"$CERT_STORE_DIR/$name.crt"
		return 1
	elif [ ! -f "$CERT_STORE_DIR/$name.csr" ] ; then
		printf "Internal Error (%s): cert Signing request %s does not exists.\n" \
			"$BASH_FUNC" \
			"$CERT_STORE_DIR/$name.csr"
		return 1
	fi

	# store the old crt and csr and retrieve serial
	local timestamp &&
	timestamp=$(date +"%Y%m%d-%H%M%s") &&
	local serial &&
	serial="$(openssl x509 -noout -serial -in "$CERT_STORE_DIR/$name.crt")" &&
	mv "$CERT_STORE_DIR/$name.csr" \
		"$CERT_ARCHIVE_DIR/$name.csr.before$timestamp" &&
	mv "$CERT_STORE_DIR/$name.crt" \
		"$CERT_ARCHIVE_DIR/$name.crt.before$timestamp" \
	|| return 1

	# now create updated cert
	serial=$(( $serial + 1)) &&
	cert_create_cert "$name" "$caname" "$serial" "$req" \
	|| return 1

	# If we would like to reuse the cst we could use something like the
	# following command. BUT we dont like it since it would ignore
	# potential changes to .reqtxt since the creation of the csr
	# openssl x509 -req -days 365 -in git.test.nafets.de.csr
	#	-CA nafetsde-ca.crt -CAkey nafetsde-ca.key -set_serial 03
	#	-out git.test.nafets.de-2018.crt

	return 0
}

##### cert_get_cert ########################################################
function cert_get_cert {
	# Parameters:
	#    1 - name of certificate (without extension)
	#    2 - name of the CA (default: nafetsde-ca)
	#    3 - reqtxt file (default: "-" means read from stdin)
	# Prerequisites:
	#    $CERT_PRIVATE_DIR/<caname>.key
	#    $CERT_STORE_DIR/<caname>.crt
	#        our CA and its key
	#    $CERT_PRIVATE_DIR/$certname.key.insecure
	#        contains a valid private key.
	# Output:
	#    $CERT_STORE_DIR/$certname.crt
	#        the updated certificate (without root cert)
	#    $CERT_STORE_DIR/$certname.fullchain.crt
	#        the updated certificate (including root cert)

	local name="$1"
	local caname="${2:-"nafetsde-ca"}"
	local req="$3" # default will be handled by called functions

	if [ -z "$name" ] ; then
		printf "Internal Error (%s): No parm, expected >= 1\n" "$BASH_FUNC"
		return 1
	fi

	if [ ! -f $CERT_STORE_DIR/$name.crt ] ; then
		# CERT does not exist yet
		cert_create_cert "$name" "$caname" "$req" || return 1
	else
		# CERT does already exist
		cert_update_cert "$name" "$caname" "$req" || return 1
	fi
	printf "%s\n" "$CERT_STORE_DIR/$name.crt"

	return 0
}

##### Main ###################################################################
# do nothing


##############################################################################
# Useful information:
#
## Standard values for certificates at our site:
# Country Name (2 letter code) [AU]:DE
# State or Province Name (full name) [Some-State]:Bayern
# Locality Name (eg, city) []:Forstern
# Organization Name (eg, company) [Internet Widgits Pty Ltd]:Stefan Schallenberg
# Organizational Unit Name (eg, section) []:
# Common Name (e.g. server FQDN or YOUR name) []:<Ziel des zertifikats>
# Email Address []:

## Display certificate:
#openssl x509 -noout -text -in a.crt

## recreate csr from crt
#openssl x509 -x509toreq -in nafets.dyndns.eu-20xx.crt -out nafets.dyndns.eu.csr -signkey nafets.dyndns.eu.key

