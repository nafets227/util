#!/bin/bash
# helmupdate.sh
# generic script to update helm chart
# (C) 2021 Stefan Schallenberg

if
	[ -z "$KUBE_NAMESPACE" ] ||
	[ -z "$release" ] ||
	[ -z "$reponame" ] ||
	[ -z "$chart" ] ||
	[ -z "$repourl" ]
then
	echo "Aborting because not all Vars are set"
	echo "    KUBE_NAMESPACE/release $KUBE_NAMESPACE/$release"
	echo "    from RepoName/chart    $reponame/$chart"
	echo "    at RepoURL             $repourl"
	exit 1
elif false ; then
	# make shellcheck happy to demonstrate vars provided from outside
	# have been set
	KUBE_NAMESPACE=""
	release=""
	reponame=""
	chart=""
	repourl=""
fi

echo "Updating"
echo "    KUBE_NAMESPACE/release $KUBE_NAMESPACE/$release"
echo "    from RepoName/chart    $reponame/$chart"
echo "    at RepoURL             $repourl"

set -x

# wait for DNS server. Sometimes this pod is starting quicker than DNS
# after reboot
while true ; do
	nslookup www.ibm.com && break
	sleep 1
	i=${i-0}
	(( i++ ))
	if [ "$i" -ge 60 ] ; then
		echo "Timed out after 60s - DNS not responding to query for www.ibm.com"
		exit 1
	fi
done

helm repo add "$reponame" "$repourl" &&
helm repo update &&

repo_ver=$(
	helm \
		-n "$KUBE_NAMESPACE" \
		search repo "$reponame/$chart" \
		-o yaml \
	| sed -n 's/^  version: //p'
	) &&

inst_ver=$(
	helm \
		-n "$KUBE_NAMESPACE" \
		list -f "$release" \
		-o yaml \
	| sed -n "s/^  chart: $chart-//p"
	)

#shellcheck disable=SC2181 # $? looks nicer here than if followed by long cmd
if [ "$?" -ne 0 ] ; then
	echo "Error finding versions installed and available. Aborting."
	exit 1
elif [ "$inst_ver" == "$repo_ver" ] ; then
	echo "Not updating, version $inst_ver is already the latest."
	exit 0
else # upgrade
	echo "upgrading."
	helm upgrade --namespace "$KUBE_NAMESPACE" "$release" "$reponame/$chart"
	exit $?
fi
