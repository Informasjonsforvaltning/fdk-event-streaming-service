#!/bin/bash

docker-compose exec schema-registry bash -c "echo '$messages'|kafka-avro-console-consumer --bootstrap-server kafka:29092 --topic mqa-events --offset earliest --partition 0 --property value.schema.id=2"
