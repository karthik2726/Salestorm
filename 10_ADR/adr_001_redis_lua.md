# ADR 001: Atomic Redis Lua Script for High-Concurrency Inventory Gating

* **Status:** Accepted
* **Deciders:** Senior System Architecture Team
* **Date:** 2026-10-05

---

## Context and Problem Statement
During flash sales, 10,000 customers attempt to purchase 100 available units of Product X simultaneously. Executing stock updates directly against relational SQL databases causes severe row-lock contention, connection pool exhaustion, and HTTP 504 timeouts. The system requires an in-memory contention gate that executes stock decrement, customer purchasing limits, and idempotency checks in a single atomic step without lock contention.

---

## Options Considered

1. **Option 1: PostgreSQL Optimistic Locking (`version` column)**
   * *Pros:* Standard SQL, no secondary datastore needed.
   * *Cons:* 99% of concurrent transactions fail version check, creating massive retry storms.
2. **Option 2: PostgreSQL Pessimistic Locking (`SELECT FOR UPDATE`)**
   * *Pros:* Simple transaction isolation.
   * *Cons:* Blocks threads sequentially; connection pools exhaust within 500ms under 10k req/s ingress.
3. **Option 3: Redis Atomic Lua Script (`EVALSHA`) [CHOSEN]**
   * *Pros:* Single-threaded execution in memory ($<1.5\text{ ms}$ processing time), handles >100,000 req/sec per cluster shard, guarantees zero lock contention.
   * *Cons:* In-memory state can diverge from PostgreSQL if Redis master crashes before DB outbox sync.

---

## Decision Outcome
**Chosen Option: Option 3 (Redis Atomic Lua Script).**
Redis serves as the fast admission gatekeeper. Once stock reaches 0, Redis triggers an event setting a `SOLD_OUT` flag on the edge CDN to shed excess traffic instantly.

---

## Consequences & Trade-Offs
* **Positive:** Eliminates database lock contention; achieves sub-20ms p95 reservation latency under extreme load.
* **Negative:** Introduces state duplication between Redis and PostgreSQL.
* **Mitigation:** Implemented automated background reconciliation sweeper and startup cache hydration protocol.
