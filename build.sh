#!/bin/bash

REGISTRY=${1:-gcr.io/jbelamaric-public}
TAG=${2:-v1.6.5}

set -e

rm -rf coredns
git clone https://github.com/coredns/coredns
mkdir coredns/docker
cp Dockerfile coredns.sh coredns/docker

cd coredns
git checkout $TAG
sed -i -e 's?kubernetes:kubernetes?kubernetai:github.com/coredns/kubernetai/plugin/kubernetai?' plugin.cfg
docker run --rm -itv $PWD:/coredns -w /coredns golang:1.12 make
cp coredns docker
cd docker
docker build . -t $REGISTRY/coredns:kubernetai-$TAG
