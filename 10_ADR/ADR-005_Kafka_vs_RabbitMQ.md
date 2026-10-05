# ADR-005: Event Streaming Infrastructure (Apache Kafka vs. RabbitMQ / SQS)

* **Status:** Accepted
* **Context:** Selecting message broker technology for high-throughput event streaming, outbox events, and outage buffer durability.
* **Options Considered:**
  1. *RabbitMQ / AWS SQS:* Good for traditional message queuing, but message deletion upon consumption limits log replayability.
  2. *Apache Kafka [CHOSEN]:* Immutable append-only commit log, 32 partition scaling by `product_id`, message replay capabilities, durable buffering during 30s service outages.
* **Decision:** Selected Apache Kafka.
* **Consequences & Trade-offs:** Higher operational complexity than SQS; provides durable buffering and horizontal consumer partition scaling.
