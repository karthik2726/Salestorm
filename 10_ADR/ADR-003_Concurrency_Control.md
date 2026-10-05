# ADR-003: Concurrency Control Strategy (Optimistic vs. Pessimistic vs. Redis Atomic Lua)

* **Status:** Accepted
* **Context:** Preventing inventory overselling when 10,000 users attempt to reserve 100 available units simultaneously.
* **Options Considered:**
  1. *Optimistic Locking (`version` column):* Causes 99% transaction aborts and retry storms under high contention.
  2. *Pessimistic Locking (`SELECT FOR UPDATE`):* Exhausts database connection pools within 500ms.
  3. *Redis Atomic Lua Script (`reserve_stock.lua`) [CHOSEN]:* Single-threaded in-memory execution ($<1.5\text{ ms}$), zero lock contention, handles >100k req/sec.
* **Decision:** Selected Redis Atomic Lua Script as fast gate, backed by PostgreSQL `CHECK(available_quantity >= 0)` safety net.
* **Consequences & Trade-offs:** Requires Redis cache hydration from PostgreSQL upon crashes; achieves sub-20ms p95 latency under extreme load.
