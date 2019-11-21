#!/bin/bash

set -e

source functions.sh

gcloud compute networks create $NETWORK --subnet-mode=custom
gcloud compute firewall-rules create $NETWORK-internal --network $NETWORK --allow tcp,udp,icmp --source-ranges $MASTERAUTHNETWORKS
#gcloud compute firewall-rules create $NETWORK-inbound --network $NETWORK --allow tcp:22 --source-ranges $WORKSTATIONCIDR

gcloud compute networks subnets create k0-subnet --network $NETWORK --range 172.16.10.0/24 --secondary-range pods=10.0.0.0/16,services=10.128.0.0/16 --region=us-central1
gcloud compute networks subnets create k1-subnet --network $NETWORK --range 172.16.11.0/24 --secondary-range pods=10.1.0.0/16,services=10.129.0.0/16 --region=us-central1

gcloud container clusters create k0 --enable-ip-alias --enable-private-nodes --master-ipv4-cidr=172.16.0.0/28    --enable-master-authorized-networks     --master-authorized-networks=$MASTERAUTHNETWORKS --network $NETWORK --subnetwork k0-subnet --zone us-central1-a --cluster-secondary-range-name=pods --services-secondary-range-name=services
gcloud container clusters create k1 --enable-ip-alias --enable-private-nodes --master-ipv4-cidr=172.16.1.0/28    --enable-master-authorized-networks     --master-authorized-networks=$MASTERAUTHNETWORKS --network $NETWORK --subnetwork k1-subnet --zone us-central1-b --cluster-secondary-range-name=pods --services-secondary-range-name=services

gcloud iam service-accounts create coredns --display-name "CoreDNS Multi-Cluster Account"
gcloud iam service-accounts keys create --iam-account $SA coredns-sa.json

gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA --role=roles/container.clusterViewer
