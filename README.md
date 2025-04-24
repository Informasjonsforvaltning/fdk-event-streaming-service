# FDK Event Streaming Service (Kafka)
This repository contains the code for the FDK Event Streaming Service, which is built on top of Apache Kafka. 
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

### Testing
The scripts in the `scripts` directory are run as part of the docker-compose process.
They are responsible for creating the necessary topics and produces a couple of messages.
