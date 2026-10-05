# Database Transaction Boundaries & Isolation Specifications

This document defines explicit ACID transaction boundaries, isolation levels, and consistency guarantees across microservices in the SALESTORM platform.

---

## 1. Microservice Transaction Boundaries

```
[Service Request Ingress]
         │
         ├── Tx-1: Reserve Stock Boundary (Inventory Svc)
         │   ├── Check & Decrement Inventory Ledger
         │   ├── Insert Inventory Reservation Record
         │   └── Insert Outbox Event (ReservationCreated)
         │   └── [COMMIT / ROLLBACK]
         │
         ├── Tx-2: Payment Settlement Boundary (Payment Svc)
         │   ├── Insert / Update Payment Record (status='SUCCESS')
         │   ├── Insert Outbox Event (PaymentConfirmed)
         │   └── [COMMIT / ROLLBACK]
         │
         └── Tx-3: Order Creation Boundary (Order Svc)
             ├── Check Consumer Idempotency (processed_events)
             ├── Insert Orders & Order Items Record
             ├── Mark processed_events
             └── [COMMIT / ROLLBACK]
```

### Transaction Boundary 1: Asynchronous Inventory Persistence (`Tx-1`)
* **Participating Operations (Atomic Block):**
  1. Update `inventory` record (conditional decrement of `available_quantity`, increment of `reserved_quantity`, `version = version + 1`).
  2. Insert record into `inventory_reservation` table (`status = 'RESERVED'`).
  3. Insert `ReservationCreated` payload into `outbox_event` table.
* **Isolation Level:** `READ COMMITTED`.
* **Consistency Guarantee:** Atomic local ACID guarantees. If inserting the reservation fails (e.g. unique constraint violation for `customer_id`), the stock decrement rolls back entirely.

### Transaction Boundary 2: Payment Execution & Outbox Entry (`Tx-2`)
* **Participating Operations (Atomic Block):**
  1. Insert or update `payment` record (`status = 'SUCCESS'`, `transaction_ref = X`).
  2. Update `inventory_reservation` status to `PAYMENT_PENDING`.
  3. Insert `PaymentConfirmed` event into `outbox_event`.
* **Isolation Level:** `READ COMMITTED`.
* **Consistency Guarantee:** Guarantees that payment state updates and event publishing to Kafka via outbox scraper never diverge.

### Transaction Boundary 3: Idempotent Order Creation (`Tx-3`)
* **Participating Operations (Atomic Block):**
  1. Insert record into `processed_event` (`event_id`, `consumer_group = 'order-service'`).
  2. Insert `orders` and associated `order_item` rows (`status = 'CONFIRMED'`).
  3. Update `inventory_reservation` status to `CONFIRMED`.
* **Isolation Level:** `READ COMMITTED`.
* **Consistency Guarantee:** Exactly-once order creation. Primary key conflict on `processed_event(event_id, consumer_group)` forces immediate transaction abort if duplicate Kafka messages arrive.

---

## 2. Isolation Level Selection & Rationale

| Transaction Context | Chosen Isolation Level | Rationale & Protection |
| :--- | :--- | :--- |
| **Inventory DB Sync** | `READ COMMITTED` | Prevents Dirty Reads. Concurrency lock contention is managed at the Redis layer or via explicit `version` column checks, eliminating expensive `SERIALIZABLE` lock escalation overhead. |
| **Order Creation Consumer** | `READ COMMITTED` | Standard transactional write performance. Unique key constraint on `(event_id, consumer_group)` handles concurrency safely without `REPEATABLE READ` serialization errors. |
| **Reconciliation Sweeper** | `READ COMMITTED` | Sweeper reads committed rows where `expires_at < NOW()`. Minimizes lock duration during bulk updates. |

---

## 3. Trade-Off Analysis

* **`READ COMMITTED` vs `SERIALIZABLE` Isolation:**
  * *Trade-off:* `READ COMMITTED` does not prevent phantom reads or non-repeatable reads within a transaction window.
  * *Justification:* `SERIALIZABLE` isolation in PostgreSQL introduces frequent serialization failures under high concurrency, forcing client retries. SALESTORM delegates real-time concurrency gating to Redis Lua scripts and relies on DB unique constraints + version checks for durability.
