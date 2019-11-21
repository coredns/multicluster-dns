# Multi-cluster discovery of headless services

This is a set of sample scripts as a proof-of-concept for multi-cluster service
discovery in GKE. This solution allows pods running in one cluster to discover
services running in another cluster using the normal cluster DNS server. It does
this by scaling down the standard kube-dns deployment and instead running a special
CoreDNS build for the cluster DNS. That CoreDNS deployment watches the API servers
for all clusters, using the [kubernetai](https://github.com/coredns/kubernetai)
plugin. The results of the discovery of services in other clusters only make sense
for headless services, and then only if the pod IPs are routable ([VPC native
mode](https://cloud.google.com/kubernetes-engine/docs/how-to/alias-ips)).
ClusterIPs are not routable; see [this
issue](https://github.com/coredns/kubernetai/issues/30) for as-yet-unrealized 
ideas on how to make this work for other types of services.

The script will create three clusters, k0, k1 and k2, in alternating zones of
whatever region you select.

*Before running, you may want to change a few things:*
* Run this from inside the directory containing all these scripts. It will
  create a kubeconfig file it needs to do deployments. Running `deploy.sh` will
  delete any file named `kubeconfig` in the current directory! Running
  `build.sh` will delete any file or directory named `coredns` in this
  directory.
* It uses your default gcloud project and account. Be sure you set these before
  running `setup.sh`.
* This uses private nodes in GKE. You'll need to setup your workstation CIDR
  in `functions.sh` in order to be able to access the master and the nodes from
  your workstation.

Once you have that all taken care of, then you:

* Run setup.sh
* Run deploy.sh
* Check this with `gcr.io/jbelamaric-public/dnstools`:

```
$ kubectl run -it --rm --restart=Never --image gcr.io/jbelamaric-public/dnstools dnstools
If you don't see a command prompt, try pressing enter.
dnstools# host hello-headless-k1
hello-headless-k1.default.svc.cluster.local has address 10.1.0.5
dnstools# host hello-headless-k0
hello-headless-k0.default.svc.cluster.local has address 10.0.1.5
dnstools# exit
```

That is showing resolving the two different headless services that are in the
two different clusters.

## Scripts
* functions.sh
  * Setup and functions used by the other scripts.
* build.sh
  * Builds a special version of CoreDNS that includes the kubernetai plugin. It
    also builds an image that sets up the service account keys so that CoreDNS
    can authenticate to the different clusters.
  * The service account setup probably should be done in an init container
    instead of an entrypoint script like this.
  * If you build this, you can push it to a registry of your choice. Right now,
    this is already built in gcr.io/jbelamaric-public/coredns:kubernetai-v1.6.5
* setup.sh
  * Creates a network, firewall rules, subnets, and secondary ranges for the
    clusters.
  * Creates three clusters, k0, k1 and k2, in different zones.
  * Creates a service account for use by CoreDNS in the clusters.
* deploy.sh
  * Deploys CoreDNS and some services in the clusters.

# CAVEATS

* It is really only meaningful to do discovery of headless services, and even
  then, only if the Pod IPs are routable between the clusters. ClusterIPs have
  no meaning outside of their cluster.
* The Corefile as written is shared across both clusters. This means that for
  service names that are the same in both clusters, it will ALWAYS return the
  address of the service in the FIRST cluster. This is for ClusterIP services
  as well, so that along with the above caveat makes this a poor way to do this.
* A better way would be to list the current cluster FIRST, then list all other
  clusters. That means a different Corefile for every cluster.
* Alternatively, you can structure the Corefile to use the standard in-cluster
  service account for the CoreDNS pod (you would need to create one and set the
  pod's serviceAccountName, see CoreDNS
  [deployment](https://github.com/coredns/deployment/tree/master/kubernetes)),
  and then just list all the clusters. This would allow the same Corefile for
  all clusters, but it would create additional connections back to the current
  cluster. That is, each CoreDNS would have:
    * Connection to its own API server using internal SA.
    * Connection to its own API server using the GCP SA.
    * Connection to each other clusters' API server using the GCP SA.
* The image that is used here uses an entry point script to setup the kubeconfig
  files for CoreDNS to authenticate to the different API servers. An init
  container that sets those up would be better.
