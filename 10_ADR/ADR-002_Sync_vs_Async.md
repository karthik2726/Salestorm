# ADR-002: Synchronous REST/gRPC vs. Asynchronous Event-Driven Architecture

* **Status:** Accepted
* **Context:** Determining communication paradigms across microservices during high-concurrency flash sales.
* **Options Considered:**
  1. *Fully Synchronous REST/gRPC:* Simple code path, but cascading latency and single-point-of-failure risks.
  2. *Hybrid Synchronous Gate + Asynchronous Event Pipeline [CHOSEN]:* Sync REST/gRPC for reservation and payment authorization; async Kafka topics for order creation, fulfillment, and notifications.
* **Decision:** Selected Hybrid model. Fast real-time operations remain synchronous; downstream fulfillment is decoupled via Kafka.
* **Consequences & Trade-offs:** Introduces eventual consistency for order UI updates (1-2s lag); gains absolute resilience during downstream service outages (e.g. 30s Order Service downtime).
