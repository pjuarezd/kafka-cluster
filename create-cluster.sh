#!/bin/sh -ex

kind create cluster --config kind-cluster.yaml
#kubernetes-dashboard
kubectl apply -f kubernetes-dashboard.yaml
kubectl apply -f kubernetes-dashboard-admin-user.yaml
kubectl -n kubernetes-dashboard create token admin-user >> admin-user.key
kubectl proxy & open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
#minio cluster
kubectl create ns minio-operator
kubectl apply -k github.com/minio/operator/\?ref\=v4.4.25
kubectl minio init
kubectl get secret console-sa -o jsonpath="{.data.token}" > minio-token.key
#strimzi
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORK_DIR=`mktemp -d -p "$DIR"`

STRTIMZI_VERSION=$(curl -sL https://api.github.com/repos/strimzi/strimzi-kafka-operator/releases/latest  | jq -r ".tag_name")
curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/$STRTIMZI_VERSION/strimzi-$STRTIMZI_VERSION.tar.gz" -s -o strimzi-$STRTIMZI_VERSION.tar.gz
tar -zxvf strimzi-$STRTIMZI_VERSION.tar.gz
