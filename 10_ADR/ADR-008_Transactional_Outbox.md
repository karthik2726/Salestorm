# ADR-008: Transactional Outbox Pattern for Guaranteed Event Publishing

* **Status:** Accepted
* **Context:** Preventing state divergence between local SQL database commits and Apache Kafka event publishing.
* **Options Considered:**
  1. *Direct Dual-Write:* Non-atomic; network drop post-DB commit causes lost Kafka events.
  2. *Transactional Outbox Pattern [CHOSEN]:* Writes domain state and `outbox_event` payload within the same local ACID transaction. An outbox scraper worker publishes events to Kafka with at-least-once delivery guarantees.
* **Decision:** Selected Transactional Outbox Pattern.
* **Consequences & Trade-offs:** ~50ms outbox polling latency; guarantees 100% dual-write consistency.
