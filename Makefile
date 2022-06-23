MINIO_VERSION ?=4.4.25

.PHONY: default

default:
	@grep '^[^#[:space:]].*:' Makefile

create-cluster:
	@kind create cluster --config kind-cluster.yaml

delete-cluster:
	@kind delete cluster --name kind-cluster

kubernetes-dashboard:
	@kubectl create ns kubernetes-dashboard
	@kubectl apply -f kubernetes-dashboard.yaml
	@kubectl apply -f kubernetes-dashboard-admin-user.yaml
	@kubectl -n kubernetes-dashboard create token admin-user >> admin-user.key
#	LOCAL ONLY, URL where dashboard is available	
#	@kubectl proxy & open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

minio-operator:
	@kubectl create ns minio-operator
	@kubectl apply -k github.com/minio/operator/\?ref\=$(MINIO_VERSION)
	@kubectl minio init
#	@kubectl get secret console-sa -o jsonpath="{.data.token}" > minio-token.key
	@kubectl apply -f minio/secret.yaml
	@kubectl -n minio-operator get secret ${$(kubectl get -n minio-operator serviceaccount console-sa -o jsonpath="{.secrets[0].name}"):-console-sa-secret} -o jsonpath="{.data.token}" | base64 --decode > minio-token.key

strimzi-operator:
	@kubectl create ns kafka
	@kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
	@kubectl apply -f deployments/strimzi/kafka-persistent-single.yaml -n kafka

kudo-operator:
	@echo todo

producer:
	@kubectl apply -f client/kafka-client-producer.yaml -n kafka
	@echo TODO: wait and see logs

consumer:
	@kubectl apply -f client/kafka-client-consumer.yaml
	@echo TODO: wait and see logs
