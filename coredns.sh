#!/bin/bash

SA=$1

shift

gcloud auth activate-service-account $SA --key-file /etc/sa/sa.json

for cluster in $*; do
  name=$(basename $cluster)
  zone=$(dirname $cluster)

  export KUBECONFIG=/root/kubeconfig.$name
  gcloud container clusters get-credentials --internal-ip --zone $zone $name
  ctx=$(grep current-context: $KUBECONFIG | cut -f 2 -d ' ')
  sed -i -e s/$ctx/$name/g $KUBECONFIG
done

# the above should be done in an init-container, really
/coredns -conf /etc/coredns/Corefile
