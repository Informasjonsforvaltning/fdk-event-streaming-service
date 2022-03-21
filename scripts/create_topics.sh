#!/bin/bash

docker-compose exec kafka kafka-topics --create --if-not-exists --partitions 1 --replication-factor 1 --topic dataset-events --bootstrap-server localhost:9092
docker-compose exec kafka kafka-topics --create --if-not-exists --partitions 1 --replication-factor 1 --topic mqa-dataset-events --bootstrap-server localhost:9092
docker-compose exec kafka kafka-topics --create --if-not-exists --partitions 1 --replication-factor 1 --topic mqa-events --bootstrap-server localhost:9092