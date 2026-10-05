# ADR-007: Distributed Transaction Management (Saga Pattern vs. Two-Phase Commit)

* **Status:** Accepted
* **Context:** Orchestrating multi-microservice transactions across Inventory, Payment, and Order domains.
* **Options Considered:**
  1. *Two-Phase Commit (2PC / XA):* Synchronous blocking locks across microservices; high latency, poor fault isolation.
  2. *Saga Pattern with Compensation Workflows [CHOSEN]:* Asynchronous choreography/orchestration where each microservice executes local transactions and triggers compensating transactions (refund + stock release) on failure.
* **Decision:** Selected Saga Pattern.
* **Consequences & Trade-offs:** Requires writing explicit compensation logic (refund + stock release); eliminates distributed database lock deadlocks.
