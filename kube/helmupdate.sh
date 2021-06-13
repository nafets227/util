#!/bin/sh
# helmupdate.sh
# generic script to update helm chart
# (C) 2021 Stefan Schallenberg

echo "Updating"
echo "    KUBE_NAMESPACE/release $KUBE_NAMESPACE/$release"
echo "    from RepoName/chart    $reponame/$chart"
echo "    at RepoURL             $repourl"

set -x

helm repo add $reponame $repourl &&
helm repo update &&

repo_ver=$(
	helm \
		-n $KUBE_NAMESPACE \
		search repo $reponame/$chart \
		-o yaml \
	| sed -n 's/^  version: //p'
	) &&

inst_ver=$(
	helm \
		-n $KUBE_NAMESPACE \
		list -f $release \
		-o yaml \
	| sed -n "s/^  chart: $chart-//p"
	)

if [ "$?" -ne 0 ] ; then
	echo "Error finding versions installed and available. Aborting."
	exit 1
elif [ "$inst_ver" == "$repo_ver" ] ; then
	echo "Not updating, version $inst_ver is already the latest."
	exit 0
else # upgrade
	echo "upgrading."
	helm upgrade --namespace $KUBE_NAMESPACE $release $reponame/$chart
	exit $?
fi
