FROM quay.io/strimzi/kafka:0.29.0-kafka-3.2.0
USER root:root
RUN mkdir -p /opt/kafka/plugins/ \
    && curl https://api.hub.confluent.io/api/plugins/confluentinc/kafka-connect-s3/versions/10.0.9/archive -o /opt/kafka/plugins/confluentinc-kafka-connect.zip \
    && unzip -d /opt/kafka/plugins /opt/kafka/plugins/confluentinc-kafka-connect.zip \
    && rm /opt/kafka/plugins/confluentinc-kafka-connect.zip 
USER 1001
