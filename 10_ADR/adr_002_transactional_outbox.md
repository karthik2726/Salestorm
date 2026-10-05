# ADR 002: Transactional Outbox Pattern for Dual-Write Consistency

* **Status:** Accepted
* **Deciders:** Senior System Architecture Team
* **Date:** 2026-10-05

---

## Context and Problem Statement
When a microservice updates its local database (e.g. persisting a payment) and subsequently publishes an event to Apache Kafka, network drops or application crashes between the DB write and the Kafka publish cause dual-write state divergence. The system must guarantee that database updates and event publishing are strictly atomic.

---

## Options Considered

1. **Option 1: Direct Dual Write (DB update then Kafka publish)**
   * *Pros:* Simple implementation code.
   * *Cons:* Non-atomic. If Kafka publish fails, DB state is persisted but downstream services never receive events.
2. **Option 2: Distributed Two-Phase Commit (2PC / XA Transactions)**
   * *Pros:* Strict cross-system atomicity.
   * *Cons:* Heavy performance overhead, high latency, poor fault isolation.
3. **Option 3: Transactional Outbox Pattern + DB Poller [CHOSEN]**
   * *Pros:* Atomic local ACID transaction writes domain state and event payload to an `outbox_event` table simultaneously. A background worker polls the outbox and publishes events to Kafka with at-least-once delivery guarantees.
   * *Cons:* Introduces a ~50ms event publishing lag.

---

## Decision Outcome
**Chosen Option: Option 3 (Transactional Outbox Pattern).**
Guarantees 100% dual-write consistency without performance penalties of distributed 2PC transactions.

---

## Consequences & Trade-Offs
* **Positive:** Absolute data consistency between microservice databases and Kafka topics.
* **Negative:** Small ~50ms outbox scraping latency.
* **Mitigation:** Consumers implement the `processed_event` database table pattern to handle duplicate at-least-once Kafka deliveries idempotently.
