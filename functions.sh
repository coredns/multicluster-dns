#!/bin/bash

NETWORK=coredns-mcsd

# Allow access to the masters from this CIDR, in addition to node and pod CIDR
WORKSTATIONCIDR=
MASTERAUTHNETWORKS=10.0.0.0/8,172.16.0.0/16${WORKSTATIONCIDR:+,$WORKSTATIONCIDR}

PROJECT=$(gcloud config get-value core/project)
SA="coredns@$PROJECT.iam.gserviceaccount.com"
ACCOUNT=$(gcloud config get-value core/account)

function get_credentials {
  name=$(basename $1)
  zone=$(dirname $1)
  export KUBECONFIG=kubeconfig
  echo "Getting credentials for $name"
  gcloud container clusters get-credentials --zone $zone $name
  ctx=$(kubectl --kubeconfig=$KUBECONFIG config get-contexts | tr -d '*' | tr -s ' ' | cut -d ' ' -f 2 | grep _$name)
  echo "Setting context name for $ctx to $name"
  kubectl --kubeconfig=$KUBECONFIG config rename-context $ctx $name
}

function deploy {
  name=$1
  sa=$2
  k0=$3
  k1=$4

  k0name=$(basename $k0)
  k0zone=$(dirname $k0)

  k1name=$(basename $k1)
  k1zone=$(dirname $k1)

  KUBECTL="kubectl --kubeconfig kubeconfig --context $name"
  echo "Creating cluster role binding for $ACCOUNT as cluster-admin in $name..."
  $KUBECTL delete clusterrolebinding $ACCOUNT-clusteradmin || echo
  $KUBECTL create clusterrolebinding $ACCOUNT-clusteradmin --clusterrole=cluster-admin --user=$ACCOUNT

  echo "Scaling existing kube-dns to 0..."
  $KUBECTL -n kube-system scale --replicas 0 deployment/kube-dns

  echo "Scaling existing kube-dns-autoscaler to 0..."
  $KUBECTL -n kube-system scale --replicas 0 deployment/kube-dns-autoscaler

  echo "Creating service account secret..."
  $KUBECTL -n kube-system delete secret coredns-sa || echo
  $KUBECTL -n kube-system create secret generic --from-file=sa.json=coredns-sa.json coredns-sa

  echo "Creating CoreDNS deployment..."
  $KUBECTL -n kube-system apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
data:
  Corefile: |
    .:53 {
        errors
        health
        log
        kubernetai cluster.local in-addr.arpa ip6.arpa {
          kubeconfig /root/kubeconfig.$k0name $k0name
          fallthrough in-addr.arpa ip6.arpa cluster.local
        }
        kubernetai cluster.local in-addr.arpa ip6.arpa {
          kubeconfig /root/kubeconfig.$k1name $k1name
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        reload
    }
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: coredns
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $sa
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: coredns
  labels:
    app: coredns
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      containers:
      - name: coredns
        image: gcr.io/jbelamaric-public/coredns:kubernetai-v1.6.1
        imagePullPolicy: Always
        args: ["$sa", "$k0", "$k1"]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        - name: sa-volume
          mountPath: /etc/sa
          readOnly: true
        - name: homedir
          mountPath: /root
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
        - name: sa-volume
          secret:
            secretName: coredns-sa
            items:
            - key: sa.json
              path: sa.json
        - name: homedir
          emptyDir: {}
EOF
}
