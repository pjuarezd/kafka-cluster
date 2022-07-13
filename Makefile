MINIO_VERSION ?=v4.4.25
DOCKER_USER ?=pjuarezd
DOCKER_EMAIl ?=pjuarezd@users.noreply.github.com
STRIMZI_VERSION ?=0.28.0
OPERATOR_NAMESPACE ?=kafka
SET_STRIMZI_VERSION = $(eval STRIMZI_VERSION=$(shell curl -sL https://api.github.com/repos/strimzi/strimzi-kafka-operator/releases/latest  | jq -r ".tag_name"))

.PHONY: default

default:
	@grep '^[^#[:space:]].*:' Makefile

create-cluster:
	@kind create cluster --config kind-cluster.yaml
	
operator-namespace:
	@kubectl create namespace $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

create-docker-login-secret: operator-namespace
	@kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=${DOCKER_USER} --docker-password=${DOCKER_HUB_PASSWORD} --docker-email=${DOCKER_EMAIl} -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

delete-cluster:
	@kind delete cluster --name kind-cluster

kubernetes-dashboard:
	@kubectl create ns kubernetes-dashboard
	@kubectl apply -f kubernetes-datshboard.yaml
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

minio-tenant:
	@kubectl create namespace minio-tenant-1  --dry-run=client -o yaml | kubectl apply -f -
	@kubectl minio tenant create minio-tenant-1   \
		--servers                 4               \
		--volumes                 4               \
		--capacity                16Ti            \
		--storage-class           standard        \
		--namespace               minio-tenant-1

strimzi-operator-simplified: opearator-namespace
	@kubectl apply -f 'https://strimzi.io/install/latest?namespace=$(OPERATOR_NAMESPACE)' -n $(OPERATOR_NAMESPACE)

install-strimzi: operator-namespace
ifeq "$(STRIMZI_VERSION)"  "latest"
	$(SET_STRIMZI_VERSION)
endif
	@curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/$(STRIMZI_VERSION)/strimzi-$(STRIMZI_VERSION).tar.gz" -s -o strimzi-$(STRIMZI_VERSION).tar.gz;
	@tar -zxvf strimzi-$(STRIMZI_VERSION).tar.gz
#Replace for Linux
#	@cd strimzi-$(STRIMZI_VERSION) && sed -i 's/namespace: .*/namespace: $(OPERATOR_NAMESPACE)/' install/cluster-operator/*RoleBinding*.yaml
#Replace for Mac
	@cd strimzi-$(STRIMZI_VERSION) && sed -i '' 's/namespace: .*/namespace: $(OPERATOR_NAMESPACE)/' install/cluster-operator/*RoleBinding*.yaml
#	@kubectl create -f strimzi-$(STRIMZI_VERSION)/install/cluster-operator/020-RoleBinding-strimzi-cluster-operator.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
#	@kubectl create -f strimzi-$(STRIMZI_VERSION)/install/cluster-operator/031-RoleBinding-strimzi-cluster-operator-entity-operator-delegation.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create -f strimzi-$(STRIMZI_VERSION)/install/cluster-operator/ -n kafka

internal-cluster: operator-namespace
	@kubectl apply -f deployments/strimzi/kafka-internal.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait kafka/cl-01 --for=condition=Ready --timeout=300s -n $(OPERATOR_NAMESPACE)

external-cluster: operator-namespace
	@kubectl apply -f deployments/strimzi/kafka-external.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait kafka/cl-02 --for=condition=Ready --timeout=300s -n $(OPERATOR_NAMESPACE)

connector-cluster: create-docker-login-secret
	@kubectl apply -f minio/kafka-connector-cluster.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

producer:
	@kubectl apply -f client/kafka-client-producer.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait Job/producer --for=condition=complete --timeout=300s -n $(OPERATOR_NAMESPACE)

consumer:
	@kubectl apply -f client/kafka-client-consumer.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl logs job/consumer -n kafka -f --since=1s

build-connector-image:
	@docker build -t docker.io/pjuarezd/minio-kafka-connector:latest minio/
	@docker push docker.io/pjuarezd/minio-kafka-connector:latest

connector: connector-cluster
	@kubectl apply -f minio/s3-sink-connector.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
