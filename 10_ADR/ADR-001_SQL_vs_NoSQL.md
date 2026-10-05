# ADR-001: Relational SQL (PostgreSQL Aurora) vs. NoSQL Datastore

* **Status:** Accepted
* **Context:** SALESTORM requires a durable primary datastore for inventory ledgers, payment settlement records, and order state machines.
* **Options Considered:**
  1. *NoSQL (DynamoDB/Cassandra):* High write throughput, but lacks multi-table ACID transactions, versioned relational checks, and schema constraints.
  2. *Relational SQL (PostgreSQL Aurora Multi-AZ) [CHOSEN]:* Strict ACID compliance, relational FK/UNIQUE constraints, and `CHECK(available_quantity >= 0)` safety net.
* **Decision:** Selected PostgreSQL Aurora Multi-AZ. High-concurrency write locks are avoided by placing a Redis atomic Lua gate in front of PostgreSQL.
* **Consequences & Trade-offs:** Sacrifices infinite horizontal DB write scaling; gains guaranteed financial audit integrity and zero data loss ($RPO = 0$).
