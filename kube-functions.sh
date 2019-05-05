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

##### kube-install - install Kubernetes objects in kube/ subdir ##############
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
function kube-install {
	local action="$1"
	local app="$2"
	local ns="${3:-test}"
	local confdir="$(realpath ${4:-./kube})"
	local envnames="$5"
	local kube_action action_desploy

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
			sed_parms="$sed_parms -e 's/\${$f}/${value//\//\\\/}/'"
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

	# @TODO create namespace and load configmaps
#
#	kubectl delete -n $ns configmap nginx.$app \
#		--cascade=true --ignore-not-found
#
#	kubectl create configmap auth.$app \
#		--from-file=$BASEDIR/auth.conf \
#		--save-config \
#		--dry-run \
#		-o yaml \
#		| kubectl apply -n $ns -f -

	#Execute Shell Scripts in confdir
	if [ ! -z "$(ls $confdir/*.sh 2>/dev/null)" ] ; then
		for f in $confdir/kube/*.sh ; do
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
			eval sed $sed_parms <$f \
			| kubectl $kube_action -n $ns -f - \
			|| return 1
		done
	fi

	#Execute yaml.delete in confdir
	if [ ! -z $(ls $confdir/*.yaml.delete 2>/dev/null) ] ; then
		for f in $BASEDIR/kube/*.yaml.delete ; do
			kubectl delete -n $ns -f $f \
				--cascade=true --ignore-not-found \
			|| return 1
		done
	fi

	return 0
}

##### kube-wait : Wait for Cluster to start all pods ################################
# Parameters:
# 1 - Minimum number of pods [optional, 1]
# 2 - Timeout to wait for machine to appear in seconds [optional, default=240]
function kube-wait {
	local readonly minPods=${1:-1}
        local readonly sleepMax=${2:-240}

        local readonly sleepNext=5

        local slept=0 # beginning

        while [ "$slept" -lt "$sleepMax" ] ; do
		PODS=$(/usr/bin/kubectl -n kube-system get pods -o name) &&
		POD_CNT=$(wc -w <<<"$PODS") &&

		POD_ACT=$(/usr/bin/kubectl \
			-n kube-system \
			wait $PODS \
			--for condition=Ready \
			--timeout=0 2>/dev/null)
		POD_WAIT_RC=$?
		POD_ACT_CNT=$(wc -l <<<"$POD_ACT")

		if [ "$POD_WAIT_RC" == 0 ] &&
		   [ "$POD_CNT" -ge "$minPods" ] ; then
			printf "Pods OK: %s/%s/%s (def/act/exp)" \
				"$POD_CNT" "$(wc -l <<<"$POD_ACT")" "$minPods"
			return 0
		fi

		printf "Waiting for pods: %s/%s/%s (def/act/exp)" \
			"$POD_CNT" "$(wc -l <<<"$POD_ACT")" "$minPods"

                printf " sleep %s seconds (%s/%s)\n" \
                        "$sleepNext" "$slept" "$sleepMax"
                sleep $sleepNext ; slept=$(( $slept + $sleepNext ))
        done

        printf "ERROR: Timed out waiting %s seconds for Kubernetes\n" \
                "$sleepMax"

        return 1
}

##### MAIN-template ##################################################################
# This can be used as template for application specific install script
function main-template {
if [ "$1" == "--config" ] ; then
	shift
	config "$@" || exit 1
	printf "Loaded config for app %s in Namespace %s\n" \
		"$app" "$ns"
else
	config "$@"
	kube-install ...
fi
}

##### MAIN ###################################################################

# do nothing ! just load functions

#test
#set -x
#export MYIP=myipvalue
#kube-install install myapp test . "MYIP"
