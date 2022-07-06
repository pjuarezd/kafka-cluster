MINIO_VERSION ?=v4.4.25
DOCKER_USER ?=pjuarezd
DOCKER_EMAIl ?=pjuarezd@users.noreply.github.com
.PHONY: default

default:
	@grep '^[^#[:space:]].*:' Makefile

create-cluster:
	@kind create cluster --config kind-cluster.yaml
create-docker-login-secret:
	@kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=${DOCKER_USER} --docker-password=${DOCKER_HUB_PASSWORD} --docker-email=${DOCKER_EMAIl} -n kafka

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
	@kubectl create namespace minio-operator --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -k github.com/minio/operator/\?ref\=${MINIO_VERSION} -n minio-operator
	@kubectl minio init
#	@kubectl get secret console-sa -o jsonpath="{.data.token}" > minio-token.key
	@kubectl apply -f minio/secret.yaml
	@kubectl -n minio-operator get secret ${$(kubectl get -n minio-operator serviceaccount console-sa -o jsonpath="{.secrets[0].name}"):-console-sa-secret} -o jsonpath="{.data.token}" | base64 --decode > minio-token.key

strimzi-operator:
	@kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

internal-cluster:
	@kubectl apply -f deployments/strimzi/kafka-internal.yaml -n kafka

external-cluster:
	@kubectl apply -f deployments/strimzi/kafka-external.yaml -n kafka

connector-cluster:
	@kubectl apply -f minio/kafka-connector-cluster.yaml -n kafka
producer:
	@kubectl apply -f client/kafka-client-producer.yaml -n kafka
	@echo TODO: wait and see logs
consumer:
	@kubectl apply -f client/kafka-client-consumer.yaml -n kafka
	@echo TODO: wait and see logs
# build-connector-image:
# 	@docker build -t docker.io/pjuarezd/minio-kafka-connector:latest minio/
#	@docker push docker.io/pjuarezd/minio-kafka-connector:latest
connector:
	@kubectl apply -f minio/s3-sink-connector.yaml -n kafka