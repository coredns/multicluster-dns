#!/bin/bash

# Generates the Corefile given two GKE cluster names
# and deploys CoreDNS

set -e

k0=${1:-us-central1-a/k0}
k1=${2:-us-central1-b/k1}

source functions.sh

rm -f kubeconfig

get_credentials $k0
get_credentials $k1

deploy $(basename $k0) $SA $k0 $k1
deploy $(basename $k1) $SA $k0 $k1


for cluster in $k0 $k1; do
  ctx=$(basename $cluster)

  kubectl --kubeconfig kubeconfig --context $ctx apply -f helloweb-deployment.yaml
  sed -e s/CLUSTERNAME/$ctx/ helloweb-service-clusterip.yaml | kubectl --kubeconfig kubeconfig --context $ctx apply -f -
  sed -e s/CLUSTERNAME/$ctx/ helloweb-service-headless.yaml | kubectl --kubeconfig kubeconfig --context $ctx apply -f -
done
