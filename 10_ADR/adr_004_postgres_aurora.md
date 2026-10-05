# ADR 004: PostgreSQL Aurora Multi-AZ as Authoritative Relational Ledger

* **Status:** Accepted
* **Deciders:** Senior System Architecture Team
* **Date:** 2026-10-05

---

## Context and Problem Statement
SALESTORM requires a durable, ACID-compliant primary datastore for inventory ledgers, payment transactions, order state machines, and outbox logs. The datastore must guarantee zero data loss ($RPO = 0$), support sub-30-second automated failover ($RTO < 30\text{s}$), and enforce strict relational constraints (`CHECK(available_quantity >= 0)`).

---

## Options Considered

1. **Option 1: NoSQL Datastore (DynamoDB / Cassandra)**
   * *Pros:* Linear write scalability.
   * *Cons:* Lacks multi-table ACID transactions, versioned relational checks, and complex join capabilities required for financial accounting ledgers.
2. **Option 2: AWS RDS PostgreSQL 16 Multi-AZ (Aurora Cluster) [CHOSEN]**
   * *Pros:* Strict ACID compliance, relational integrity constraints, synchronous WAL replication across 3 AZs ($RPO = 0$), automated primary failover ($RTO < 30\text{s}$).
   * *Cons:* Vertical write scaling limitations on single primary writer.

---

## Decision Outcome
**Chosen Option: Option 2 (PostgreSQL Aurora Multi-AZ).**

---

## Consequences & Trade-Offs
* **Positive:** Guaranteed financial audit integrity and zero data loss.
* **Negative:** Primary writer database instance represents a write throughput ceiling (~2,500 write tx/sec).
* **Mitigation:** Real-time flash sale inventory contention is offloaded to Redis memory; PostgreSQL receives batched, non-contended asynchronous updates via transactional outbox workers.
