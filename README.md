# FDK Event Streaming Service (Kafka)
This repository contains the framework for the FDK Event Streaming Service, which is built on top of Apache Kafka. 
The service is designed to handle event streaming and processing for the Data.norge.no ecosystem.

## Getting Started

These instructions will help you set up the project locally for development and testing purposes.

## Prerequisites
Ensure you have the following installed:
- Docker
- bash
- curl

### Running locally
Clone the repository:
```sh
git clone https://github.com/Informasjonsforvaltning/fdk-event-streaming-service.git
cd fdk-event-streaming-service
```

Run local cluster:
```sh
docker compose up -d
```

The local cluster is a single-node KRaft cluster (no ZooKeeper). If you have a
`kafka-data` directory from before the KRaft switch, delete it first:
`rm -rf kafka-data`.

## Deployment

Kubernetes manifests live in `deploy/` (Kustomize base + overlays per
environment).

### Users and access

Clients authenticate with SASL/SCRAM-SHA-512 on port 9094 and are limited by
ACLs to the topics and consumer group they use. Users and ACLs are stored in
the KRaft metadata log; the controller's data disk holds the copy the quorum
starts from.

To add a client:

1. Add a key named after the service, with its password, to the
   `kafka-scram-users-<env>` secret in Secret Manager for each environment.
2. In fdk-infra, add a `kafka-user-<service>` ExternalSecret that delivers the
   credential to the service's namespace.
3. Add the service's grants to the `ACLS` list in
   `deploy/base/kafka-acls/kafka-acls-job.yaml`.

On the next deploy the `kafka-users` Job creates the SCRAM credential from the
secret and the `kafka-acls` Job applies the grants. Both lists are additive:
removing a user or a grant is done by hand with `kafka-configs` and
`kafka-acls`.

### Controller disk

The controller refuses to start on an unformatted data directory, because an
empty metadata log would have no topics, users or ACLs and no admin user for
the brokers to log in with. If the disk is lost, restore it from a snapshot.
Only when bootstrapping a brand new cluster, set `FORMAT_NEW_CLUSTER=true` on
the controller for the first start; it formats the directory with the admin
credential from the `kafka-scram-users` secret. Remove the variable again
afterwards, or the guard is disabled for every later start on an empty disk.

### Testing
The scripts in the `scripts` directory are run as part of the docker-compose process.
They are responsible for creating the necessary topics and produces a couple of messages.
