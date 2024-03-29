MINIO_VERSION ?=v4.5.0
DOCKER_USER ?=pjuarezd
DOCKER_EMAIl ?=pjuarezd@users.noreply.github.com
STRIMZI_VERSION ?=latest
OPERATOR_NAMESPACE ?=kafka
MINIO_TENANT_NAMESPACE ?=minio-tenant-1
SET_STRIMZI_VERSION = $(eval STRIMZI_VERSION=$(shell curl -sL https://api.github.com/repos/strimzi/strimzi-kafka-operator/releases/latest  | jq -r ".tag_name"))
GET_MINIO_CERT = $(shell kubectl get secret  -n $(MINIO_TENANT_NAMESPACE) $(MINIO_TENANT_NAMESPACE)-tls -o "jsonpath={.data['public\.crt']}" | base64 --decode)
GET_CA_CERT = $(shell kubectl get secret  -n $(MINIO_TENANT_NAMESPACE) $(MINIO_TENANT_NAMESPACE)-tls -o "jsonpath={.data['public\.crt']}" | base64 --decode)
KEYSTOREPASS ?=changeit
.PHONY: default

default:
	@grep '^[^#[:space:]].*:' Makefile

create-kind-cluster:
	@kind create cluster --config kind-cluster.yaml
	
delete-kind-cluster:
	@kind delete cluster --name kind-cluster

operator-namespace:
	@kubectl create namespace $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

create-docker-login-secret: operator-namespace
	@kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=${DOCKER_USER} --docker-password=${DOCKER_HUB_PASSWORD} --docker-email=${DOCKER_EMAIl} -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

create-minio-secrets:
# This secret doesn't exists when minio is not setup for tls
	@kubectl get secret -n $(MINIO_TENANT_NAMESPACE) $(MINIO_TENANT_NAMESPACE)-tls -o "jsonpath={.data['public\.crt']}" | base64 --decode > $(MINIO_TENANT_NAMESPACE)-tls.pem
	@kubectl get configmap -n kafka kube-root-ca.crt -o "jsonpath={.data['ca\.crt']}" >> kube-root-ca.crt
	@rm -f connector/truststore.p12
	@keytool -keystore connector/truststore.p12 -storetype pkcs12 -alias minio.$(MINIO_TENANT_NAMESPACE).svc.cluster.local -storepass $(KEYSTOREPASS)  -import -file  $(MINIO_TENANT_NAMESPACE)-tls.pem -noprompt
	@keytool -keystore connector/truststore.p12 -storetype pkcs12 -alias ca.crt -storepass $(KEYSTOREPASS) -import -file kube-root-ca.crt -noprompt
	@kubectl create secret generic $(MINIO_TENANT_NAMESPACE)-truststore -n "$(OPERATOR_NAMESPACE)" --from-file=truststore.p12=connector/truststore.p12 --from-literal=truststore.password=$(KEYSTOREPASS)  --from-literal=truststore.type=pkcs12 --dry-run=client -oyaml | kubectl apply -f -
#	@kubectl create secret generic $(MINIO_TENANT_NAMESPACE)-ca-cert -n "$(OPERATOR_NAMESPACE)" --from-file=minio.$(MINIO_TENANT_NAMESPACE).svc.cluster.local=$(MINIO_TENANT_NAMESPACE)-tls.pem
#	@kubectl create secret generic kube-root-ca -n "$(OPERATOR_NAMESPACE)" --from-file=ca.crt=kube-root-ca.crt
	@kubectl apply -f minio/bucket-credentials-secret.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

kubernetes-dashboard:
	@kubectl create ns kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f kubernetes-dashboard.yaml
	@kubectl apply -f kubernetes-dashboard-admin-user.yaml
	@kubectl -n kubernetes-dashboard create token admin-user >> admin-user.key
#	LOCAL ONLY, URL where dashboard is available	
#	@kubectl proxy & open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

minio-operator:
	@kubectl create namespace minio-operator --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -k github.com/minio/operator/\?ref\=${MINIO_VERSION} -n minio-operator
	@kubectl minio init
	@kubectl apply -f minio/console-sa-secret.yaml -n minio-operator
	@kubectl wait --for=condition=ready pod -l name=minio-operator -n minio-operator --timeout=600s
	@kubectl -n minio-operator get secret console-sa-secret -o jsonpath="{.data.token}" | base64 --decode > minio-operator.key

minio-tenant:
	@kubectl create namespace $(MINIO_TENANT_NAMESPACE)  --dry-run=client -o yaml | kubectl apply -f -
	@kubectl minio tenant create $(MINIO_TENANT_NAMESPACE)   \
		--servers                 3                          \
		--volumes                 6                          \
		--capacity                16Ti                       \
		--storage-class           standard                   \
		--namespace               $(MINIO_TENANT_NAMESPACE)
#	@kubectl wait pod --for=condition=ready -l name=minio -n $(MINIO_TENANT_NAMESPACE)  --timeout=3600s
setup-bucket:
	@kubectl apply -f minio/setup-bucket.yaml -n $(MINIO_TENANT_NAMESPACE)
	@kubectl wait --for=condition=complete Job/minio-setup --timeout=300s -n $(MINIO_TENANT_NAMESPACE)

strimzi-operator-simplified: opearator-namespace
	@kubectl apply -f 'https://strimzi.io/install/latest?namespace=$(OPERATOR_NAMESPACE)' -n $(OPERATOR_NAMESPACE)

strimzi-operator: operator-namespace
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

strimzi-cluster: operator-namespace
	@kubectl apply -f deployments/strimzi/kafka-internal.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait kafka/cl-01 --for=condition=Ready --timeout=300s -n $(OPERATOR_NAMESPACE)

external-cluster: operator-namespace
	@kubectl apply -f deployments/strimzi/kafka-external.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait kafka/cl-02 --for=condition=Ready --timeout=300s -n $(OPERATOR_NAMESPACE)

connector-user:
	@kubectl apply -f connector/connector-user.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

connector-cluster: connector-user
	@kubectl apply -f connector/kafka-connector-cluster.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

producer:
	@kubectl apply -f client/kafka-client-producer.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait Job/producer --for=condition=complete --timeout=300s -n $(OPERATOR_NAMESPACE)

consumer:
	@kubectl apply -f client/kafka-client-consumer.yaml -n $(OPERATOR_NAMESPACE)
	@kubectl wait pod --selector=job-name=consumer --for=condition=ready --timeout=300s -n $(OPERATOR_NAMESPACE)
	@kubectl logs Job/consumer -n $(OPERATOR_NAMESPACE) -f 

build-connector-image: create-docker-login-secret
	@docker build -t docker.io/pjuarezd/minio-kafka-connector:latest --no-cache connector/
	@docker push docker.io/pjuarezd/minio-kafka-connector:latest

image-test:
	@rm -rf connector/s3-sink/*
	@cd ../../confluentinc/kafka-connect-storage-cloud && mvn install
#cd ../../confluentinc/kafka-connect-storage-cloud && mvn dependency:copy-dependencies -DoutputDirectory=/mydeps
	@cp ../../confluentinc/kafka-connect-storage-cloud/kafka-connect-s3/target/components/packages/confluentinc-kafka-connect-s3-*.zip connector/s3-sink/
	@docker build -t pjuarezd/minio-kafka-connector:test --no-cache -f connector/Dockerfile.image-test connector/
	@kind load docker-image pjuarezd/minio-kafka-connector:test --name kind-cluster

build-connector-cluster: create-docker-login-secret
	@kubectl apply -f connector/kafka-connector-cluster-build.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

connector-s3:
	@kubectl apply -f connector/s3-sink-connector.yaml -n $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

elasticsearch:
	@kubectl create -f https://download.elastic.co/downloads/eck/2.7.0/crds.yaml
	@kubectl apply -f https://download.elastic.co/downloads/eck/2.7.0/operator.yaml
	@kubectl apply -f elasticsearch/cluster.yaml
	@kubectl apply -f elasticsearch/kibana.yaml