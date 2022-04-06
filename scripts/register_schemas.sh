#!/bin/bash

curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{ "schema": "{ \"name\": \"MQAEvent\", \"namespace\": \"no.fdk.mqa\", \"type\": \"record\", \"fields\": [ { \"name\": \"type\", \"type\": { \"type\": \"enum\", \"name\": \"MQAEventType\", \"symbols\": [\"URLS_CHECKED\", \"MODEL_CHECKED\", \"DCAT_COMPLIANCE_CHECKED\", \"SCORE_CALCULATED\"] } }, {\"name\": \"fdkId\", \"type\": \"string\"}, {\"name\": \"graph\", \"type\": \"string\"}, {\"name\": \"timestamp\", \"type\": \"long\", \"logicalType\": \"timestamp-millis\"} ] }" }' \
  http://localhost:8081/subjects/mqa-event/versions

echo ""
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{ "schema": "{ \"name\": \"DatasetEvent\", \"namespace\": \"no.fdk.dataset\", \"type\": \"record\", \"fields\": [ { \"name\": \"type\", \"type\": { \"type\": \"enum\", \"name\": \"DatasetEventType\", \"symbols\": [\"DATASET_HARVESTED\"] } }, {\"name\": \"fdkId\", \"type\": \"string\"}, {\"name\": \"graph\", \"type\": \"string\"}, {\"name\": \"timestamp\", \"type\": \"long\", \"logicalType\": \"timestamp-millis\"} ] }" }' \
  http://localhost:8081/subjects/dataset-event/versions