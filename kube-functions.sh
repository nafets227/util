#!/bin/bash
#
# kube-functions.sh
#
# Utility functions for Kubernetes
#
# (C) 2018 Stefan Schallenberg

##### kube-getIP #############################################################
function kube-getIP {
	local result
	result=$(dig +short $1)
	rc=$?
	if [ $rc != "0" ] ; then
		printf "Error getting IP of %s.\n" "$1" >&2
		return 1
	elif [ -z "$result" ] ; then
		printf "DNS name %s not defined.\n" "$1" >&2
		return 1;
	fi

	printf "%s\n" "$result"
	return 0
}

##### kube-inst_init - Initialize Kubernetes Installation ####################
# Parameter:
#   1 - action [install|delete]
#   2 - stage [prod|preprod|test|testtest] where to install
#   3 - app Application name to be assigne to kubernetes tag
#   4 - namespace (only use if non-stan dard, standard is based on stage)
#   5 - Kube Configfile (defaults to ~/.kube/$stage.conf )
# Environment Variables set on exit
#   KUBE_CONFIGFILE name of Kubeconfig with access credentials
#   KUBE_ACTION     action
#   KUBE_STAGE      stage
#   KUBE_NAMESPACE  Namespeace to be used
#   KUBE_APP        Application name to be used in Labels
function kube-inst_init {
	local action="$1"
	local stage="${2:-preprod}"
	local app="$3"
	local ns="$4"
	local configfile="$5"

	if [ "$action" == "install" ] || [ "$action" == "delete" ] ; then
		KUBE_ACTION="$action"
	elif [ "$action" == "config" ] ||
	     [ "$action" == "test" ] ||
	     [ "$action" == "none" ] ; then
		# may lead to errors if calling subsequent functiond
		KUBE_ACTION="$action"
		action=config
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

	if [ "$KUBE_ACTION" == "install" ] ; then
		# Create Namespace if it does not exist yet
		kubectl \
			--kubeconfig $KUBE_CONFIGFILE \
			get namespace $KUBE_NAMESPACE &>/dev/null ||
		kubectl \
			--kubeconfig $KUBE_CONFIGFILE \
			create namespace $KUBE_NAMESPACE &>/dev/null ||
		return 1
	fi

	return 0
}

##### kube-inst_internal-verify-initialised ##################################
function kube-inst_internal-verify-initialised {
	if  [ ! -r "$KUBE_CONFIGFILE" ] ||
	    [ -z "$KUBE_ACTION" ] ||
	    [ -z "$KUBE_NAMESPACE" ] ||
	    [ -z "$KUBE_STAGE" ] ||
	    [ -z "$KUBE_APP" ] ; then
		printf "kube-inst_init has not been called. \n"
		printf "KUBE_CONFIGFILE, KUBE_ACTION, KUBE_NAMESPACE, "
		printf "KUBE_STAGE or KUBE_APP is not set.\n"
		return 1
	else
		return 0
	fi
}

##### kube-inst_exec - Execute installation
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - confdir
#   2 - envnames
function kube-inst_exec {
	local confdir="$(realpath ${1:-./kube})"
	local envnames="$2"

	kube-inst_internal-verify-initialised || return 1

	KUBECONFIG=$KUBE_CONFIGFILE kube-inst_internal \
		"$KUBE_ACTION" \
		"$KUBE_APP" \
		"$KUBE_NAMESPACE" \
		"$confdir" \
		"$envnames KUBE_APP"
	rc="$?"

	unset KUBE_CONFIGFILE KUBE_ACTION KUBE_NAMESPACE KUBE_APP

	return $rc
}

##### kube-inst_helm - install Helm Chart #####
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - release (=name) of helm chart
#   2 - url of source
#   3ff - [optional] variables to set (var=value)
function kube-inst_helm {
	local release="$1"
	local sourceurl="$2"
	shift 2

	kube-inst_internal-verify-initialised || return 1

	if [ "$KUBE_ACTION" == "install" ] ; then
		local action=""
		if helm status \
				--kubeconfig $KUBE_CONFIGFILE \
				--namespace $KUBE_NAMESPACE \
				$release >/dev/null 2>/dev/null ; then
			action=upgrade
		else
			action=install
		fi

		local parms=""
		for p in $* ; do
			parms+=" --set $p"
		done

		helm $action \
			--kubeconfig $KUBE_CONFIGFILE \
			--namespace $KUBE_NAMESPACE \
			$parms \
			$release \
			$sourceurl &&
		/bin/true || return 1
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		helm uninstall \
			--kubeconfig $KUBE_CONFIGFILE \
			--namespace $KUBE_NAMESPACE \
			$release &&
		/bin/true || return 1
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
			"$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

	return 0
}

##### kube-inst_tls-secret - install Kubernetes Secret using cert* helper ####
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - name of secret
#   2 - name of the CA (default: nafetsde-ca)
# Prerequisites:
#   $CERT_STORE_DIR/<caname>.crt
#        our CA and its key
#   stdin as .reqtxt file
#        the details of the fields certificate
function kube-inst_tls-secret {
	local secretname="$1"
	local caname="$2"

	kube-inst_internal-verify-initialised || return 1

	if [ -z "$secretname" ] ; then
		printf "%s: Error. Got no or empty secret name.\n" \
			"$FUNCNAME"
		return 1
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		kube_action="apply"
		action_display="Installing"
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		kube_action="delete"
		action_display="Deleting"
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

	# @TODO handle delete correctly, do not create a new cert !
	printf "creating secret %s ... " "$secretname"

	local cert_key_fname cert_fname
        cert_key_fname=$(cert_get_key $secretname) &&
        cert_fname=$(cert_get_cert $secretname $caname) &&

	kubectl --kubeconfig $KUBE_CONFIGFILE \
		create secret tls $secretname \
		--cert=$cert_fname \
		--key=$cert_key_fname \
		--save-config \
		--dry-run \
		-o yaml \
	| kubectl --kubeconfig $KUBE_CONFIGFILE $kube_action -n $KUBE_NAMESPACE -f - \
	|| return 1

	return 0
}

##### kube-inst_generic-secret - install Kubernetes Secret using cert* helper ########
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - name of secret
#   2ff - name of file(s)
function kube-inst_generic-secret {
	local secretname="$1"
	shift

	kube-inst_internal-verify-initialised || return 1

	if [ -z "$secretname" ] ; then
		printf "%s: Error. Got no or empty secret name.\n" \
			"$FUNCNAME"
		return 1
	elif [ -z "$1" ] ; then
		printf "%s: Error. Got no or empty filename.\n" \
			"$FUNCNAME"
		return 1
	# Do not check if fname exists.
	# it may be also a directory or a string like logicalname=realname
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		kube_action="apply"
		action_display="Installing"
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		kube_action="delete"
		action_display="Deleting"
	else
		printf "%s: Error. Action \$KUBE_ACTION=%s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi
	printf "creating secret %s ... " "$secretname"

	local fromfilearg=""
	for a in "$@" ; do
		fromfilearg+=" --from-file=$a"
	done

	kubectl --kubeconfig $KUBE_CONFIGFILE \
		create secret generic $secretname \
		$fromfilearg \
		--save-config \
		--dry-run \
		-o yaml \
	| kubectl --kubeconfig $KUBE_CONFIGFILE $kube_action -n $KUBE_NAMESPACE -f - \
	|| return 1

	return 0
}

##### kube-inst_configmap - install Kubernetes Configmap ####################
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - name of configmap
#   2ff - name of file(s)
function kube-inst_configmap {
	local cmapname="$1"
	shift

	kube-inst_internal-verify-initialised || return 1

	if [ -z "$cmapname" ] ; then
		printf "%s: Error. Got no or empty configmap name.\n" \
			"$FUNCNAME"
		return 1
	elif [ -z "$1" ] ; then
		printf "%s: Error. Got no or empty filename.\n" \
			"$FUNCNAME"
		return 1
	# Do not check if fname exists.
	# it may be also a directory or a string like logicalname=realname
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		kube_action="apply"
		action_display="Installing"
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		kube_action="delete"
		action_display="Deleting"
	else
		printf "%s: Error. Action \$KUBE_ACTION=%s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi
	printf "creating configmap %s ... " "$secretname"

	local fromfilearg=""
	for a in "$@" ; do
		fromfilearg+=" --from-file=$a"
	done

	kubectl --kubeconfig $KUBE_CONFIGFILE \
		create configmap $cmapname \
		$fromfilearg \
		--save-config \
		--dry-run \
		-o yaml \
	| kubectl --kubeconfig $KUBE_CONFIGFILE $kube_action -n $KUBE_NAMESPACE -f - \
	|| return 1

	return 0
}

##### kube-inst_nfs-volume - Install NFS Volume
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - share
#   2 - path [optional, default depends on share]
function kube-inst_nfs-volume {
	local share="$1"
	local path="$2"

	local readonly nfsserver="${path%%:*}"
	local readonly nfspath="${path##*:}"

	kube-inst_internal-verify-initialised || return 1

	if [ -z "$share" ] ; then
		printf "%s: Error. Got no or empty share name.\n" \
			"$FUNCNAME"
		return 1
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		kube_action="apply"
		action_display="Installed"
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		kube_action="delete --wait=false"
		action_display="Deleted"
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

        #### Make sure directory exists on server
	if [ "$KUBE_ACTION" == "install" ] ; then
		ssh $nfsserver \
			"test -d /srv/nfs4/$nfspath" \
			'||' "mkdir -p /srv/nfs4/$nfspath" \
			|| return 1
	fi
	# when deleting we leave the data untouched !

	#DEBUG# printf "Adding PV %s as %s:%s\n" "$share.$app.$stage" "$nfsserver" "$path"
	#### Setup Persistent Volume
	kubectl --kubeconfig $KUBE_CONFIGFILE $kube_action -f - <<-EOF &&
		apiVersion: v1
		kind: PersistentVolume
		metadata:
		  name: $share.$KUBE_APP.$KUBE_STAGE
		  annotations:
		    volume.beta.kubernetes.io/storage-class: "nafets"
		  labels:
		    state: "$KUBE_STAGE"
		    app: "$KUBE_APP"
		    share: "$share"
		spec:
		  capacity:
		    storage: 100Mi
		  accessModes:
		    - ReadWriteMany
		  nfs:
		    path: $nfspath
		    server: $nfsserver
		  persistentVolumeReclaimPolicy: Retain

		---

		apiVersion: v1
		kind: PersistentVolumeClaim
		metadata:
		  name: $share.$KUBE_APP
		  namespace: $KUBE_NAMESPACE
		  annotations:
		    volume.beta.kubernetes.io/storage-class: "nafets"
		  labels:
		    app: "$KUBE_APP"
		    share: "$share"
		spec:
		  accessModes:
		    - ReadWriteMany
		  resources:
		    requests:
		      storage: 100Mi
		  selector:
		    matchLabels:
		      state: "$KUBE_STAGE"
		      app: "$KUBE_APP"
		      share: "$share"
		EOF
        /bin/true || return 1

        printf "%s Volume %s (app=%s, stage=%s) for %s\n" \
                "$action_display" "$share" "$KUBE_APP" "$KUBE_STAGE" "$path"

        return 0
}

##### kube-inst_host-volume - Install Host Volume
# Prerequisite: kube-inst_init has been called
# Parametets:
#   1 - share
#   2 - path [optional, default depends on share]
function kube-inst_host-volume {
	local share="$1"
	local path="$2"

	kube-inst_internal-verify-initialised || return 1

	if [ -z "$share" ] ; then
		printf "%s: Error. Got no or empty share name.\n" \
			"$FUNCNAME"
		return 1
	fi

	if [ "$KUBE_ACTION" == "install" ] ; then
		kube_action="apply"
		action_display="Installed"
	elif [ "$KUBE_ACTION" == "delete" ] ; then
		kube_action="delete --wait=false"
		action_display="Deleted"
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi

	#### Make sure directory exists
	if [ "$KUBE_ACTION" == "install" ] ; then
		[ -d "$path" ] || mkdir -p $path || return 1
	fi
	# when deleting we leave the data untouched !

	#DEBUG# printf "Adding PV %s as %s:%s\n" "$share.$app.$stage" "$nfsserver" "$path"
	#### Setup Persistent Volume
	kubectl --kubeconfig $KUBE_CONFIGFILE $kube_action -f - <<-EOF &&
		apiVersion: v1
		kind: PersistentVolume
		metadata:
		  name: $share.$KUBE_APP.$KUBE_STAGE
		  annotations:
		    volume.beta.kubernetes.io/storage-class: "nafets"
		  labels:
		    state: "$KUBE_STAGE"
		    app: "$KUBE_APP"
		    share: "$share"
		spec:
		  capacity:
		    storage: 100Mi
		  accessModes:
		    - ReadWriteMany
		  hostPath:
		    path: $path
		  persistentVolumeReclaimPolicy: Retain

		---

		apiVersion: v1
		kind: PersistentVolumeClaim
		metadata:
		  name: $share.$KUBE_APP
		  namespace: $KUBE_NAMESPACE
		  annotations:
		    volume.beta.kubernetes.io/storage-class: "nafets"
		  labels:
		    app: "$KUBE_APP"
		    share: "$share"
		spec:
		  accessModes:
		    - ReadWriteMany
		  resources:
		    requests:
		      storage: 100Mi
		  selector:
		    matchLabels:
		      state: "$KUBE_STAGE"
		      app: "$KUBE_APP"
		      share: "$share"
		EOF
        /bin/true || return 1

        printf "%s Volume %s (app=%s, stage=%s) for %s\n" \
                "$action_display" "$share" "$KUBE_APP" "$KUBE_STAGE" "$path"

        return 0
}

##### kube-inst_internal - install Kubernetes objects in kube/ subdir ##############
# DEPRECATED
#   This function is Deprecated, please use kube-inst_init and kube-inst_exec
#   instead
# Parameter: 
#   1 - action [ install | delete ]
#   2 - app Application name to be assigned to kubernetes tag
#   3 - ns  Namespace for kubernetes objects [default:test]
#   4 - confdir Directory containing all yamls and templates 
#       [default=./kube]
#   5 - envnames [ default=none ]
#       you can  give alist of names to be environized. All words in .template files
#       inside the configdir that match a name in the list will be replaced by teh
#       value of the environment variable with that name.
#       Example:
#       envnames="MYNAME MYIP"
#       Environment variable MYNAME="mynamevalue"
#       Envrionment variabddle MYIP="myipvalue"
#       my.yaml.template:
#		value=${MYNAME}
#               ip=${MYIP}
#	will be transformed to
#  		value=mynamevalue
#		ip=myipvalue
#	before the yaml file will be processed by kubernetes.
function kube-inst_internal {
	local action="$1"
	local app="$2"
	local ns="$3"
	local confdir="$(realpath ${4:-./kube})"
	local envnames="$5"
	local kube_action action_display

	##### checking parameters
	if [ "$#" -lt 2 ] ; then
		printf "%s: Error. received %s parms (Exp >=2 ).\n" \
			"$FUNCNAME" "$#"
		return 1
	fi

	if [ "$action" == "install" ] ; then
		kube_action="apply"
		action_display="Installing"
	elif [ "$action" == "delete" ] ; then
		kube_action="delete"
		action_display="Deleting"
	else
		printf "%s: Error. Action (Parm1) %s unknown." \
		       "$FUNCNAME" "$1"
		printf " Must be \"install\" or \"delete\".\n"
		return 1
	fi


	if [ ! -d $confdir ] ; then
		printf "%s: Error confdir \"%s\" is no directory.\n"
		return 1
	fi

	##### Prepare Environizing
	sed_parms=""
	if [ ! -z "$envnames" ] ; then  for f in $envnames ; do
		if [[ -v $f ]] ; then
			eval "value=\$$f"
			sed_parms="$sed_parms -e 's/\${$f}/${value//\//\\\/}/g'"
		else
			printf "%s: variable for envname %s not defined.\n" \
				"$FUNCNAME" "$f"
		fi
	done; fi
	#DEBUG
	#printf "sed_parms=%s\n" "$sed_parms"
	#set -x

	##### Action !
	printf "%s kube-app \"%s\" in namespace \"%s\"" \
		"$action_display" "$app" "$ns"
	printf " (Env: %s) from \"%s\".\n" \
       		"$envnames" "$confdir"
	for f in $envnames ; do
		eval "value=\$$f"
		printf "\t %s=%s\n" "$f" "$value"
	done

	#Execute Shell Scripts in confdir
	if [ ! -z "$(ls $confdir/*.sh 2>/dev/null)" ] ; then
		for f in $confdir/*.sh ; do
			printf "Loading Kubeconfig %s ... " "$(basename $f)"
			. $f --$action || return 1
		done
	fi

	#Execute yaml in confdir
	if [ ! -z "$(ls $confdir/*.yaml 2>/dev/null)" ] ; then
		for f in $confdir/*.yaml ; do
			printf "Loading Kubeconfig %s ... " "$(basename $f)"
			kubectl $kube_action -n $ns -f $f || \
				kubectl replace -n $ns -f $f \
			|| return 1
		done
	fi

	#Execute yaml.template in confdir
	if [ ! -z "$(ls $confdir/*.yaml.template 2>/dev/null)" ] ; then
		for f in $confdir/*.yaml.template ; do
			printf "Loading Kubeconfig %s ... " "$(basename $f)"
			#debug printf "YAML with templace parms replaced: \n"
			#debug eval sed $sed_parms <$f
			eval sed $sed_parms <$f \
			| kubectl $kube_action -n $ns -f - \
			|| return 1
		done
	fi

	#Execute yaml.delete in confdir
	if [ ! -z $(ls $confdir/*.yaml.delete 2>/dev/null) ] ; then
		for f in $confdir/*.yaml.delete ; do
			kubectl delete -n $ns -f $f \
				--cascade=true --ignore-not-found \
			|| return 1
		done
	fi

	return 0
}

##### MAIN-template ##################################################################
# This can be used as template for application specific install script
function config-template {
	kube-inst_init \
		"action [install|delete]" \
		"stage [prod|preprod|test|testtest] where to install"
		"app Application name to be assigne to kubernetes tag"
		"namespace (only use if non-standard, standard is based on stage)"
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
	/bin/true || return 1
fi
}

##### MAIN ###################################################################

# do nothing ! just load functions
