# ZooKeeper → KRaft migration and Confluent Platform 8.x upgrade

Confluent Platform 8.x (Apache Kafka 4.x) has no ZooKeeper support at all: the
`cp-kafka` 8.x image refuses to start unless `KAFKA_PROCESS_ROLES` and
`CLUSTER_ID` are set, and there is no `cp-zookeeper` 8.x image. Kafka 4.x also
has no ZooKeeper→KRaft migration code, so the migration **must be completed on
7.9.x (Kafka 3.9)** before the image bump.

Topic data, `_schemas` and consumer offsets are preserved throughout. Log
retention is infinite in prod, so this is the only acceptable path.

The migration follows [KIP-866](https://cwiki.apache.org/confluence/display/KAFKA/KIP-866+ZooKeeper+to+KRaft+Migration)
and is rolled out as four sequential PRs. Each PR deploys to staging on open and
to prod + demo on merge, so **verify staging before merging** and verify prod
before starting the next step.

| Step | PR content | Images | ZooKeeper | Rollback |
|------|------------|--------|-----------|----------|
| 1 | Add `kafka-controller` in migration mode, brokers enter migration mode | 7.9.10 | running, authoritative | yes: revert PR |
| 2 | Brokers switch to KRaft mode | 7.9.10 | running, dual-written | yes: revert PR |
| 3 | Controller finalizes, ZooKeeper removed | 7.9.10 | deleted | **no** |
| 4 | Bump everything to 8.3.2 | 8.3.2 | – | downgrade images only |

The whole sequence was rehearsed locally on 2026-09-29 with the same
container topology (separate ZooKeeper, controller and broker) and the exact
env sets below: topic data, `_schemas`-style topics and consumer-group offsets
survived every step, including the 8.3.2 bump and the metadata finalization.

Topology stays as it is today: one controller per environment (same
availability as the single ZooKeeper node it replaces), one broker in
staging/demo and three in prod. If prod should get three controllers, add
`kafka-controller-2`/`-3` overlays in step 1 following the `deploy/prod/kafka`
layout, and list all three in `KAFKA_CONTROLLER_QUORUM_VOTERS` on controllers
and brokers. Changing the static voter set after step 1 means another rolling
restart of every node, so decide before merging step 1.

## Before step 1: per-environment prerequisites

### Create the controller disk

The controller keeps the KRaft metadata log on its own persistent disk (9G,
same as ZooKeeper). The existing Kafka and ZooKeeper disks are managed in
terraform (`terraform/dev/disks-staging.tf`, `terraform/dev/disks-demo.tf`,
`terraform/prod/disks-prod.tf` in the infrastructure repo), so add the new
disks there next to the `*-zookeeper-1` definitions and apply before opening
the PR:

| Environment | Disk name | Project |
|-------------|-----------|---------|
| staging | `fdk-dev-staging-kafka-controller-1` | digdir-fdk-dev |
| demo | `fdk-dev-demo-kafka-controller-1` | digdir-fdk-dev |
| prod | `fdk-prod-kafka-controller-1` | digdir-fdk-prod |

Zone `europe-north1-a`, 9 GB, same disk type as the ZooKeeper disk. The
ZooKeeper disk definitions are removed from terraform again in step 3.

### Read the cluster id

The KRaft controller must be formatted with the id of the **existing** cluster,
otherwise it refuses to migrate. Read it from a running broker:

```sh
kubectl -n staging exec kafka-1-0 -- kafka-cluster cluster-id --bootstrap-server localhost:9092
kubectl -n demo    exec kafka-1-0 -- kafka-cluster cluster-id --bootstrap-server localhost:9092
kubectl -n prod    exec kafka-1-0 -- kafka-cluster cluster-id --bootstrap-server localhost:9092
```

Put each value into `CLUSTER_ID` in
`deploy/<env>/kafka-controller/kafka-controller-1-patch.yaml`, replacing the
`REPLACE_WITH_<ENV>_CLUSTER_ID` placeholder. Do this **before** opening the PR,
since opening it deploys to staging.

## Step 1: controller in migration mode (this PR)

What changes:

- New app `kafka-controller` (`deploy/base/kafka-controller`, overlays per
  environment, new jobs in both workflows between zookeeper and kafka).
  It runs `cp-kafka` with `KAFKA_PROCESS_ROLES=controller`,
  `KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE=true` and
  `KAFKA_ZOOKEEPER_CONNECT` pointing at the existing ZooKeeper.
- Brokers (`deploy/base/kafka/kafka-statefulset.yaml`) stay in ZooKeeper mode
  but get `KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE=true`,
  `KAFKA_CONTROLLER_QUORUM_VOTERS`, `KAFKA_CONTROLLER_LISTENER_NAMES`,
  `CONTROLLER:PLAINTEXT` in the listener map and
  `KAFKA_INTER_BROKER_PROTOCOL_VERSION=3.9`.
- `docker-compose.yml` becomes a single-node KRaft cluster (combined
  broker+controller, no ZooKeeper). Local data is not migrated:
  `rm -rf kafka-data` before `docker compose up`.

Deploy order is zookeeper → kafka-controller → kafka → schema-registry. Once
the last broker has restarted with the migration flag, the controller migrates
the ZooKeeper metadata automatically and becomes the active controller. The
brokers keep running in ZooKeeper mode ("dual-write": the controller writes
metadata to both KRaft and ZooKeeper).

Verify:

```sh
# Controller went PRE_MIGRATION -> MIGRATION and is now the active controller (id 101)
kubectl -n <env> logs kafka-controller-1-0 | grep -E 'ZK migration state|Completed migration'
kubectl -n <env> exec kafka-controller-1-0 -- kafka-metadata-quorum --bootstrap-controller localhost:9093 describe --status
# Data still there:
kubectl -n <env> exec kafka-1-0 -- kafka-topics --bootstrap-server localhost:9092 --describe
```

Expect one broker crash-loop iteration if a broker pod is recreated faster
than its ZooKeeper session expires: it fails registration with
`NodeExistsException ... /brokers/ids/N` and starts cleanly on the next
restart. That is ZooKeeper-mode behaviour, not a migration problem.

Rollback: revert the PR. The brokers drop the migration flags and elect a
ZooKeeper controller again; delete the `kafka-controller-1` StatefulSet by hand
(the deploy workflow only applies, it never deletes).

## Step 2: brokers to KRaft mode

In `deploy/base/kafka/kafka-statefulset.yaml`:

- remove `KAFKA_ZOOKEEPER_CONNECT`, `KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE`
  and `KAFKA_INTER_BROKER_PROTOCOL_VERSION`
- add `KAFKA_PROCESS_ROLES=broker`
- keep `KAFKA_CONTROLLER_QUORUM_VOTERS`, `KAFKA_CONTROLLER_LISTENER_NAMES` and
  the listener map

In every `deploy/<env>/kafka/.../kafka-N-patch.yaml`:

- rename `KAFKA_BROKER_ID` to `KAFKA_NODE_ID` (same value)
- add `CLUSTER_ID` with the same value as the controller in that environment

The brokers keep their data directory. The image's `kafka-storage format` step
sees the existing `meta.properties` ("already formatted") and skips, and the
broker upgrades the file to KRaft format on start.

Verify: every broker logs `Kafka Server started` from `KafkaRaftServer` with
`process.roles = [broker]`, topics and consumer groups are intact, and the
KRaft quorum lists the controller as Leader and every broker as Observer:

```sh
kubectl -n <env> exec kafka-controller-1-0 -- kafka-metadata-quorum --bootstrap-controller localhost:9093 describe --replication
kubectl -n <env> exec kafka-1-0 -- kafka-consumer-groups --bootstrap-server localhost:9092 --list
```

Rollback: revert the PR. Kafka 3.9 supports moving brokers back to ZooKeeper
mode as long as the controller is still in migration mode (step 3 not done).

## Step 3: finalize and remove ZooKeeper (point of no return)

1. In `deploy/base/kafka-controller/kafka-controller-statefulset.yaml` remove
   `KAFKA_ZOOKEEPER_METADATA_MIGRATION_ENABLE` and `KAFKA_ZOOKEEPER_CONNECT`.
   On restart the controller logs `Loaded ZK migration state of MIGRATION.
   Completing the ZK migration` and stops dual-writing; ZooKeeper is now stale.
2. In the same PR delete `deploy/base/zookeeper`, `deploy/*/zookeeper` and the
   `deploy-zookeeper*` jobs from both workflows, and point the
   `kafka-controller` jobs' `needs` at nothing (staging) / the previous
   environment (prod → demo).
3. After the merge has rolled out everywhere, delete the ZooKeeper resources by
   hand, since the workflow never deletes:

```sh
kubectl -n <env> delete statefulset zookeeper-1
kubectl -n <env> delete service zookeeper-1
kubectl -n <env> delete pvc zookeeper-1-claim0
kubectl delete pv fdk-<...>-zookeeper-1
# then remove the *-zookeeper-1 disk from terraform once you are sure nothing else needs it
```

Verify: `kafka-metadata-quorum ... describe --status` still shows the
controller as leader, brokers keep serving, and the controller logs no
ZooKeeper connection attempts.

## Step 4: bump to Confluent Platform 8.3.2

Bump `confluentinc/cp-kafka` (controller and brokers) and
`confluentinc/cp-schema-registry` to `8.3.2` in `deploy/base/**` and
`docker-compose.yml`. Kafka's upgrade order for KRaft is controllers first,
then brokers, which the workflow order already enforces.

Things to know about 8.x / Kafka 4.x:

- Clients older than Kafka 2.1 cannot connect. All FDK services use current
  client libraries, but check anything unusual before merging.
- `inter.broker.protocol.version` no longer exists (already removed in step 2).
- Logging moved to log4j2; `KAFKA_LOG4J_ROOT_LOGLEVEL` still works in the image.
- The 8.x image ships `KAFKA_ADVERTISED_LISTENERS=""` as a built-in env var and
  no longer unsets it for controller-only nodes, so the controller fails with
  `Configuration 'advertised.listeners' must not be empty`. The `command:`
  override in the controller StatefulSet (added in step 1) works around it.
- The cluster keeps running at metadata version 3.9-IV0 until it is bumped
  explicitly (8.3.2 supports up to 4.3-IV0). After the rollout is stable,
  finalize it so 4.x features (kraft.version 1, transaction.version 2, ...)
  are switched on:

```sh
kubectl -n <env> exec kafka-1-0 -- kafka-features --bootstrap-server localhost:9092 describe
kubectl -n <env> exec kafka-1-0 -- kafka-features --bootstrap-server localhost:9092 upgrade --release-version 4.3
```

  This is irreversible in the sense that images older than the new metadata
  version can no longer start, so do it last.

Rollback before finalizing the metadata version: set the images back to 7.9.10.
