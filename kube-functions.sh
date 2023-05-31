#!/usr/bin/env bash
#
# kube-functions.sh
#
# Utility functions for Kubernetes
#
# (C) 2018 Stefan Schallenberg

##### kube-inst_init - Initialize Kubernetes Installation ####################
function kube-inst_init {
	# Parameter:
	#   1 - action [install|delete|config]
	#   2 - stage [prod|preprod|test|testtest] where to install
	#   3 - app Application name to be assigne to kubernetes tag
	#   4 - namespace (only use if non-stan dard, standard is based on stage)
	#   5 - Kube Configfile (defaults to ~/.kube/$stage.conf )
	# Environment Variables set on exit
	#   KUBE_CONFIGFILE name of Kubeconfig with access credentials
	#   KUBE_ACTION      action
	#   KUBE_CLI_ACTION  action to be used in kubectl cli
	#   KUBE_ACTION_DISP action to be displayed to the user with -ing
	#   KUBE_STAGE       stage
	#   KUBE_NAMESPACE   Namespeace to be used
	#   KUBE_APP         Application name to be used in Labels
	local action="$1"
	local stage="${2:-preprod}"
	local app="$3"
	local ns="$4"
	local configfile="$5"

	if [ "$action" == "install" ] ; then
		KUBE_ACTION="$action"
		KUBE_CLI_ACTION="apply"
		KUBE_ACTION_DISP="Installing"
	elif [ "$action" == "delete" ] ; then
		KUBE_ACTION="$action"
		KUBE_CLI_ACTION="delete"
		KUBE_ACTION_DISP="Deleting"
	elif [ "$action" == "config" ] ; then
		KUBE_ACTION="$action"
		KUBE_CLI_ACTION="error" # produce error if anything should be executed
		KUBE_ACTION_DISP="Configuring"
	else
		printf "Invalid Action %s\n" "$action"
		return 1
	fi

	KUBE_CONFIGFILE="${configfile:-$HOME/.kube/$stage.conf}"
	if [ ! -r "$KUBE_CONFIGFILE" ] ; then
		printf "Kubeconfigfile %s does not exist or is not readable.\n" \
			"$KUBE_CONFIGFILE"
		unset KUBE_CONFIGFILE
		return 1
	fi

	KUBE_STAGE="$stage"
	KUBE_APP="$app"
	KUBE_NAMESPACE="${ns:-$KUBE_STAGE}"

	return 0
}

##### kube-inst_internal-verify-initialised ##################################
function kube-inst_internal-verify-initialised {
	if 	 [ ! -r "$KUBE_CONFIGFILE" ] ||
			[ -z "$KUBE_ACTION" ] ||
			[ -z "$KUBE_CLI_ACTION" ] ||
			[ -z "$KUBE_ACTION_DISP" ] ||
			[ -z "$KUBE_NAMESPACE" ] ||
			[ -z "$KUBE_STAGE" ] ||
			[ -z "$KUBE_APP" ] ; then
		printf "kube-inst_init has not been called. \n"
		printf "KUBE_CONFIGFILE, KUBE_ACTION, KUBE_CLI_ACTION, "
		printf "KUBE_ACTION_DISP, KUBE_NAMESPACE, "
		printf "KUBE_STAGE or KUBE_APP is not set.\n"
		return 1
	elif [ "$KUBE_ACTION" == "config" ] ; then
		printf "cannot execute with KUBE_ACTION=config\n"
		return 1
	else
		return 0
	fi
}

##### kube-inst_internal-create_namespace ####################################
function kube-inst_internal-create_namespace {
	if [ "$KUBE_ACTION" == "install" ] ; then
		# Create Namespace if it does not exist yet
		kubectl \
			--kubeconfig "$KUBE_CONFIGFILE" \
			get namespace "$KUBE_NAMESPACE" &>/dev/null ||
		kubectl \
			--kubeconfig "$KUBE_CONFIGFILE" \
			create namespace "$KUBE_NAMESPACE" ||
		return 1
	fi
}


##### kube-inst_internal-environize ##########################################
function kube-inst_internal-environize {
	# Environize stdin to stdout
	# Parameters:
	#	1 - envnames
	#	stdin - Input File (contains "${<envname>}" to be replaced)
	#	stdout - Output File (with replaced valued)
	local envnames="$1"

	##### Prepare Environizing
	sed_parms=""
	if [ -n "$envnames" ] ; then  for f in $envnames ; do
		if [[ -v $f ]] ; then
			local internal_env_value
			eval "internal_env_value=\$$f"
			sed_parms="$sed_parms -e 's/\${$f}/${internal_env_value//\//\\\/}/g'"
		else
			printf "%s: variable for envname %s not defined.\n" \
				"${FUNCNAME[0]}" "$f" >&2
		fi
	done; fi
	#DEBUG
	#printf "sed_parms=%s\n" "$sed_parms"
	#set -x

	if [ -n "$sed_parms" ] ; then
		#shellcheck disable=SC2086 # sed_parms contains multiple parms
		eval sed ${sed_parms//$'\n'/\\n} || return 1
	else
		cat
	fi

	return 0
}

##### kube-inst_internal-exec ################################################
function kube-inst_internal-exec {
	# Execute a Template File
	# Parameters:
	#   1 - Name of the templace file. Can be "-" for stdin
	#   2 - Name of Environment variables to substitute. Canb be empty in which
	#       case no substitution takes place.
	#   3ff - Kubectl options
	local file="$1"
	shift
	local envnames="$1"
	shift

	if [ "$file" == "-" ] ; then
		file="/dev/stdin"
	fi
	kube-inst_internal-environize "$envnames" <"$file" |
		kubectl \
			--kubeconfig "$KUBE_CONFIGFILE" \
			"$KUBE_CLI_ACTION" \
			-n "$KUBE_NAMESPACE" \
			"$@" \
			-f -

	rc=$?
	if [ "$KUBE_ACTION" == "delete" ] ; then
		return 0 # never fail on delete
	fi

	return $rc
}

##### kube-inst_exec - Execute installation ##################################
function kube-inst_exec {
	# Prerequisite: kube-inst_init has been called
	# Parameters:
	#   1 - confdir Directory containing all yamls and templates
	#       [default=./kube]
	#   2 - envnames [ default=none ]
	#       you can  give alist of names to be environized. All words in .template files
	#       inside the configdir that match a name in the list will be replaced by teh
	#       value of the environment variable with that name.
	#       Example:
	#       envnames="MYNAME MYIP"
	#       Environment variable MYNAME="mynamevalue"
	#       Envrionment variabddle MYIP="myipvalue"
	#       my.yaml.template:
	#           value=${MYNAME}
	#          ip=${MYIP}
	#       will be transformed to
	#  	        value=mynamevalue
	#           ip=myipvalue
	#       before the yaml file will be processed by kubernetes.
	local confdir envnames
	confdir="$(realpath "${1:-./kube}")" || return 1
	envnames="$2 KUBE_APP"

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	##### checking parameters
	if [ "$#" -lt 2 ] ; then
		printf "%s: Error. received %s parms (Exp >=2 ).\n" \
			"${FUNCNAME[0]}" "$#"
		return 1
	fi

	if [ ! -d "$confdir" ] ; then
		printf "%s: Error confdir \"%s\" is no directory.\n" \
			"${FUNCNAME[0]}" "$confdir"
		return 1
	fi

	##### Action !
	printf "%s kube-app \"%s\" in namespace \"%s\"" \
		"$KUBE_ACTION_DISP" "$KUBE_APP" "$KUBE_NAMESPACE"
	printf " (Env: %s) from \"%s\".\n" \
		"$envnames" "$confdir"
	for f in $envnames ; do
		eval "value=\$$f"
		printf "\t %s=%s\n" "$f" "$value"
	done

	# set shellopt nullglob and reset to previous state on return
	#shellcheck disable=SC2064
	trap "$(shopt -p nullglob)" RETURN
	shopt -s nullglob

	#Execute Shell Scripts in confdir
	for f in "$confdir"/*.sh ; do
		printf "Loading Kubeconfig %s ... " "$(basename "$f")"
		#shellcheck disable=SC1090 # cannot parse dynamic parm statically
		. "$f" "--$KUBE_ACTION" || return 1
	done

	#Execute yaml in confdir
	for f in "$confdir"/*.yaml ; do
		printf "Loading Kubeconfig %s ... " "$(basename "$f")"
		kube-inst_internal-exec "$f" || return 1
	done

	#Execute yaml.template in confdir
	for f in "$confdir"/*.yaml.template ; do
		printf "Loading Kubeconfig %s ... " "$(basename "$f")"
		kube-inst_internal-exec "$f" "$envnames" || return 1
	done

	#Execute yaml.delete in confdir
	for f in "$confdir"/*.yaml.delete ; do
		kubectl delete -n "$ns" -f "$f" \
			--cascade=true --ignore-not-found \
		|| return 1
	done

	unset KUBE_CONFIGFILE KUBE_ACTION KUBE_NAMESPACE KUBE_APP

	return 0
}

##### kube-inst_helm2 - install Helm Chart from repo #########################
function kube-inst_helm2 {
	# A CronJob will also update the helm chart daily, if Version is not set
	# Parametets:
	#   1 - release =local instance name of helm chart (unique in Kube namespace)
	#   2 - repo URL
	#	3 - repo Local Name (must be unique across all projects!)
	#   4 - chart (name in repo)
	#	5 - Version [optional, default=""]
	#	    if set, install this version of chart and dont auto-update
	#   6 - envnames [optional, default=""]
	#   stdin - yaml file for values
	local release="$1"
	local repourl="$2"
	local reponame="$3"
	local chart="$4"
	local version="$5"
	local envnames="$6"

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if		[ -z "$release" ] ||
			[ -z "$repourl" ] ||
			[ -z "$reponame" ] ||
			[ -z "$chart" ] ; then
		printf "Error: Empty parms \"%s\"  \"%s\" \"%s\" \"%s\"\n" \
			"$release" "$repourl" "$reponame" "$chart"
		return 1
	fi

	local prm_version cronjobsuspend
	if [ -n "$version" ]; then
		prm_version="--version $version"
		cronjobsuspend="true"
	else
		prm_version=""
		cronjobsuspend="false"
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		helm repo add "$reponame" "$repourl" && # does not fail if already exists
		helm repo update &&
		true || return 1

		if ! inputyaml=$(kube-inst_internal-environize "$envnames") ; then
			printf "Error environizing HELM values\n"
			return 1
		fi

		#shellcheck disable=SC2086 # prm_version conains multiple parms
		if ! helm upgrade --install \
			--kubeconfig "$KUBE_CONFIGFILE" \
			--namespace "$KUBE_NAMESPACE" \
			--values - \
			$prm_version \
			"$release" \
			"$reponame/$chart" \
			<<<"$inputyaml"
		then
			printf "Error in helm upgrade --install %s\n" \
				"$release $reponame/$chart"
			printf "\tValues File:\n%s\n" "$inputyaml"
			return 1
		fi
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		# do not stop on error, try to delete everything
		helm uninstall \
			--kubeconfig "$KUBE_CONFIGFILE" \
			--namespace "$KUBE_NAMESPACE" \
			"$release"
		helm repo remove "$reponame"
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
			"${FUNCNAME[0]}" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

	#----- Setup auto update CronJob
	local cronjobname="helmupdate-$release"
	local envnameshelmupdate=""
	envnameshelmupdate+=" KUBE_NAMESPACE"
	envnameshelmupdate+=" KUBE_APP"
	envnameshelmupdate+=" cronjobname"
	envnameshelmupdate+=" cronjobsuspend"
	envnameshelmupdate+=" release"
	envnameshelmupdate+=" reponame"
	envnameshelmupdate+=" repourl"
	envnameshelmupdate+=" chart"
	echo "$cronjobname $cronjobsuspend $release $reponame $repourl $chart" >/dev/null

	kube-inst_configmap \
		"$cronjobname" \
		"helmupdate.sh=$(dirname "${BASH_SOURCE[0]}")/kube/helmupdate.sh" &&
	kube-inst_internal-exec \
		"$(dirname "${BASH_SOURCE[0]}")/kube/helmupdate.cronjob.yaml.template" \
		"$envnameshelmupdate" \
	|| return 1

	return 0
}

##### kube-inst_testhelm2 - test helm chart installed ########################
function kube-inst_testhelm2 {
	# Parameters:
	#   1 - release =local instance name of helm chart (unique in Kube namespace)
	local release="$1"

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$release" ] ; then
		printf "Error: Empty value for parm release\n"
		return 1
	elif [ "$KUBE_ACTION" != "install" ] ; then
		printf "Error: testhelm only allowed in install phase\n"
		return 1
	fi

	# wait for chart install to complete
	# currently disabled as first example, jenkins, does this inside the chart tests
	# helm status \
	#	--kubeconfig $KUBE_CONFIGFILE \
	#	--namespace $KUBE_NAMESPACE \
	#	$release -o json | \
	# jq  -r '.info.status'
	# should return "deployed".

	helm test \
		--kubeconfig "$KUBE_CONFIGFILE" \
		--namespace "$KUBE_NAMESPACE" \
		"$release"
	rc="$?"
	if [ "$rc" != "0" ] ; then
		# helm test --logs currently (2022-04) does not work
		# maybe https://github.com/helm/helm/pull/10603 will solve it.
		# So we workaround identifying the pods ourselves.
		pods=$( kubectl get pods \
			--kubeconfig "$KUBE_CONFIGFILE" \
			--namespace "$KUBE_NAMESPACE" \
			--output jsonpath='{.items[?(@.metadata.annotations.helm\.sh/hook=="test-success")].metadata.name}'
		) &&
		for pod in $pods ; do
			printf -- "----- Logs of Pod %s -----\n" "$pod"
			kubectl logs \
				--kubeconfig "$KUBE_CONFIGFILE" \
				--namespace "$KUBE_NAMESPACE" \
				--all-containers \
				"$pod"
			printf -- "----- End of Logs of Pod %s -----\n" "$pod"
			done
	fi

	return $rc
}

##### kube-inst_helm - install Helm Chart from URL ###########################
function kube-inst_helm {
	# DEPRECATED
	#   This function is deprecated, please use kube-inst_helm2
	#   instead
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - release (=name) of helm chart
	#   2 - url of source
	#   3ff - [optional] variables to set (var=value)
	#   stdin - yaml file for values
	local release="$1"
	local sourceurl="$2"
	shift 2

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ "$KUBE_ACTION" == "install" ] ; then
		local parms=""
		for p in "$@" ; do
			parms+=" --set $p"
		done

		#shellcheck disable=SC2086 # parms contains multiple parms
		helm upgrade --install \
			--kubeconfig "$KUBE_CONFIGFILE" \
			--namespace "$KUBE_NAMESPACE" \
			$parms \
			--values - \
			"$release" \
			"$sourceurl" &&
		true || return 1
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		helm uninstall \
			--kubeconfig "$KUBE_CONFIGFILE" \
			--namespace "$KUBE_NAMESPACE" \
			"$release" &&
		true || return 1
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
			"${FUNCNAME[0]}" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

	return 0
}

##### kube-inst_tls-secret - install Kubernetes Secret using cert* helper ####
function kube-inst_tls-secret {
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - name of secret
	#   2 - name of the CA
	# Prerequisites:
	#   $CERT_STORE_DIR/<caname>.crt
	#        our CA and its key
	#   stdin as .reqtxt file
	#        the details of the fields certificate
	local secretname="$1"
	local caname="$2"

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$secretname" ] ; then
		printf "%s: Error. Got no or empty secret name.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$caname" ] ; then
		printf "%s: Error. Got no or empty ca name.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	printf "%s secret %s ... " "$KUBE_ACTION_DISP" "$secretname"

	if [ "$KUBE_ACTION" == "delete" ] ; then
		kubectl --kubeconfig "$KUBE_CONFIGFILE" \
			"$KUBE_CLI_ACTION" \
			-n "$KUBE_NAMESPACE" \
			secret "$secretname" \
		|| return 1
	elif [ "$KUBE_ACTION" == "install" ] ; then
		local cert_key_fname cert_fname
		cert_key_fname=$(cert_get_key "$secretname") &&
		cert_fname=$(cert_get_cert "$secretname" "$caname") &&

		kubectl --kubeconfig "$KUBE_CONFIGFILE" \
			create secret tls "$secretname" \
			"--cert=$cert_fname" \
			"--key=$cert_key_fname" \
			--save-config \
			--dry-run=client \
			-o yaml \
		| kube-inst_internal-exec "-" "" \
		|| return 1
	fi

	return 0
}

##### kube-inst_generic-secret - install Kubernetes Secret using cert* helper ########
function kube-inst_generic-secret {
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - name of secret
	#   2ff - name of file(s)
	local secretname="$1"
	shift

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$secretname" ] ; then
		printf "%s: Error. Got no or empty secret name.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$1" ] ; then
		printf "%s: Error. Got no or empty filename.\n" \
			"${FUNCNAME[0]}"
		return 1
	# Do not check if fname exists.
	# it may be also a directory or a string like logicalname=realname
	fi

	printf "%s secret %s ... " "$KUBE_ACTION_DISP" "$secretname"

	local fromfilearg=""
	for a in "$@" ; do
		fromfilearg+=" --from-file=$a"
	done

	#shellcheck disable=SC2086 # fromfilearg contains multiple parms
	kubectl --kubeconfig "$KUBE_CONFIGFILE" \
		create secret generic "$secretname" \
		$fromfilearg \
		--save-config \
		--dry-run=client \
		-o yaml \
	| kube-inst_internal-exec "-" "" \
	|| return 1

	return 0
}

##### kube-inst_text-secret - install Kubernetes Secret using cert* helper ########
function kube-inst_text-secret {
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - name of secret
	#   2 - content (text) of the secret
	local secretname="$1"
	shift

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$secretname" ] ; then
		printf "%s: Error. Got no or empty secret name.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$1" ] ; then
		printf "%s: Error. Got no or empty content.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	printf "%s secret %s ... " "$KUBE_ACTION_DISP" "$secretname"

	local fromliteralarg=""
	for a in "$@" ; do
		fromliteralarg+=" --from-literal=$a"
	done

	#shellcheck disable=SC2086 # fromliteralarg contains multiple args
	kubectl --kubeconfig "$KUBE_CONFIGFILE" \
		create secret generic "$secretname" \
		$fromliteralarg \
		--save-config \
		--dry-run=client \
		-o yaml \
	| kube-inst_internal-exec "-" "" \
	|| return 1

	return 0
}

##### kube-inst_configmap2 - install Kubernetes Configmap ####################
function kube-inst_configmap2 {
	# Also in the files environizing will be executed
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - name of configmap2
	#   2 - envnames [optional, default=""]
	#   3ff - name of file(s)
	local cmapname="$1"
	shift
	local envnames="$1"
	shift

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$cmapname" ] ; then
		printf "%s: Error. Got no or empty configmap name.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$1" ] ; then
		printf "%s: Error. Got no or empty filename.\n" \
			"${FUNCNAME[0]}"
		return 1
	# Do not check if fname exists.
	# it may be also a directory or a string like logicalname=realname
	fi

	printf "%s configmap %s ... " "$KUBE_ACTION_DISP" "$cmapname"

	local fromfilearg=""
	for a in "$@" ; do
		fromfilearg+=" --from-file=$a"
	done

	#shellcheck disable=SC2086 # fromfilearg contains multiple args
	kubectl --kubeconfig "$KUBE_CONFIGFILE" \
		create configmap "$cmapname" \
		$fromfilearg \
		--save-config \
		--dry-run=client \
		-o yaml \
	| kube-inst_internal-exec "-" "$envnames" \
	|| return 1

	return 0
}

##### kube-inst_configmap - install Kubernetes Configmap ####################
function kube-inst_configmap {
	# DEPRECATED
	#   This function is deprecated, please use kube-inst_configmap2
	#   instead
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - name of configmap
	#   2ff - name of file(s)
	local cmapname="$1"
	shift

	kube-inst_configmap2 "$cmapname" "" "$@"

	return $?
}

##### kube-inst_nfs-volume - Install NFS Volume ##############################
function kube-inst_nfs-volume {
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - share
	#   2 - path [optional, default depends on share]
	#   3 - owner [optional] - set owner of share
	#       e.g. root:root or 1000:1000 or 1000 or :1000
	local share="$1"
	local path="$2"
	local owner="$3"

	local -r nfsserver="${path%%:*}"
	local -r nfspath="${path##*:}"
	local opt=""

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$share" ] ; then
		printf "%s: Error. Got no or empty share name.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	printf "%s NFS-Volume %s (app=%s, stage=%s) for %s\n" \
		"$KUBE_ACTION_DISP" "$share" "$KUBE_APP" "$KUBE_STAGE" "$path"

	#### Make sure directory exists on server
	if [ "$KUBE_ACTION" == "install" ] ; then
		ssh -n -o StrictHostKeyChecking=no "$nfsserver" \
			"test -d /srv/nfs4/$nfspath" \
			'||' "mkdir -p /srv/nfs4/$nfspath" \
			|| return 1

		if [ -n "$owner" ] ; then
			ssh -n -o StrictHostKeyChecking=no "$nfsserver" \
				"chown -R $owner /srv/nfs4/$nfspath" \
				|| return 1
		fi
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		# when deleting we leave the data untouched !
		opt="--wait=0"
	fi

	kube-inst_internal-exec \
		"$(dirname "${BASH_SOURCE[0]}")/kube/nfsVolume.yaml.template" \
		"KUBE_APP KUBE_STAGE share nfspath nfsserver KUBE_NAMESPACE" \
		$opt

	return $?
}

##### kube-inst_host-volume - Install Host Volume ############################
function kube-inst_host-volume {
	# Prerequisite: kube-inst_init has been called
	# Parametets:
	#   1 - share
	#   2 - path [optional, default depends on share]
	local share="$1"
	local path="$2"
	local opt=""

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$share" ] ; then
		printf "%s: Error. Got no or empty share name.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	printf "%s Host-Volume %s (app=%s, stage=%s) for %s\n" \
		"$KUBE_ACTION_DISP" "$share" "$KUBE_APP" "$KUBE_STAGE" "$path"

	if [ "$KUBE_ACTION" == "delete" ] ; then
		opt="--wait=0"
	fi

	kube-inst_internal-exec \
		"$(dirname "${BASH_SOURCE[0]}")/kube/hostVolume.yaml.template" \
		"KUBE_APP KUBE_STAGE share path KUBE_NAMESPACE" \
		$opt

	return $?
}

##### kube-inst_local-volume - Install Local Volume ##########################
function kube-inst_local-volume {
	# Prerequisite: kube-inst_init has been called
	# Parameters:
	#   1 - share
	#   2 - value (e.g. hostname -no FQDN, just hostname)
	#   3 - path [optional, default depends on share]
	#   4 - volume Mode [optional, default "Filesystem"]
	#   5 - key (default kubernetes.io/hostname)
	local share="$1"
	local value="$2"
	local path="$3"
	local volmode="${4:-"Filesystem"}"
	local key="${5:-"kubernetes.io/hostname"}"
	local opt=""

	kube-inst_internal-verify-initialised &&
	kube-inst_internal-create_namespace &&
	true || return 1

	if [ -z "$share" ] ; then
		printf "%s: Error. Got no or empty share name.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$value" ] ; then
		printf "%s: Error. Got no or empty value.\n" \
			"${FUNCNAME[0]}"
		return 1
	elif [ -z "$path" ] ; then
		printf "%s: Error. Got no or empty path.\n" \
			"${FUNCNAME[0]}"
		return 1
	fi

	if [ "$KUBE_ACTION" == "delete" ] ; then
		opt="--wait=0"
	fi

	printf "%s Local Volume %s (app=%s, stage=%s, mode=%s) for %s=%s : %s \n" \
		"$KUBE_ACTION_DISP" "$share" "$KUBE_APP" "$KUBE_STAGE" "$volmode" \
		"$key" "$value" "$path"

	kube-inst_internal-exec \
		"$(dirname "${BASH_SOURCE[0]}")/kube/localVolume.yaml.template" \
		"KUBE_APP KUBE_STAGE share key value path volmode KUBE_NAMESPACE" \
		$opt

	return $?
}

##### MAIN-template ##################################################################
function config-template {
	# This can be used as template for application specific install script
	kube-inst_init \
		"action [install|delete]" \
		"stage [prod|preprod|test|testtest] where to install" \
		"app Application name to be assigne to kubernetes tag" \
		"namespace (only use if non-standard, standard is based on stage)" \
		"kubeconfig (only us if not standard ~/.kube/$stage.conf"
	if [ "$KUBE_STAGE" == "prod" ] ; then
		MYVAL="prodvalue"
	elif [ "$KUBE_STAGE" == "preprod" ] ; then
		MYVAL="preprodvalue"
	elif [ "$KUBE_STAGE" == "test" ] ; then
		MYVAL="testvalue"
	else
		return 1
	fi

	echo "MYVAL=$MYVAL"
}

function main-template {
	if [ "$1" == "--config" ] ; then
		shift
		config "$@" || exit 1
		printf "Loaded config for app %s in Namespace %s\n" \
			"$app" "$ns"
	else
		config "$@" &&
		kube-inst_exec  "./kube" "MYVAL" &&
		true || return 1
	fi
}

##### MAIN ###################################################################
# do nothing ! just load functions
