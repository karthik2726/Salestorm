# AI-Assisted System Validation & Simulation Engine

This directory contains the automated `asyncio` simulation script (`simulate.py`) that models 10,000 concurrent buyers, atomic Redis Lua gate reservation, payment settlement, network retry idempotency, and 30-second Order Service outage recovery.

---

## 🚀 How to Run the Simulation

Execute the script using `uv` (recommended) or standard Python 3.8+:

```bash
# Using uv (pre-configured)
uv run simulate.py

# Or using standard python
python simulate.py
```

---

## 📊 Expected Output

```
======================================================================
  SALESTORM FLASH-SALE SYSTEM SIMULATION (10,000 BUYERS)
======================================================================

======================================================================
                     SYSTEM ASSERTION RESULTS                       
======================================================================
 1. Sold Stock <= 100                 : [PASS] (Sold: 100)
 2. Stock Never Negative (Available>=0): [PASS] (Available: 0)
 3. No Duplicate Reservations/Customer: [PASS] (Unique Res: 103)
 4. No Duplicate Payments             : [PASS] (Payments: 100)
 5. No Duplicate Orders               : [PASS] (Orders: 100)
 6. 100% Paid Payments -> Orders      : [PASS] (Paid: 100, Orders: 100)
 7. Stock Conservation (Avail+Res+Sold=100): [PASS] (0 + 0 + 100 = 100)
======================================================================
```

---

## 🎯 Assertion-to-Design Mapping Matrix

| Assertion # | Evaluated Condition | Design Assumption / Document Validated |
| :--- | :--- | :--- |
| **Assertion 1** | `sold_stock <= 100` | Zero oversell guarantee via atomic Lua script ([`08_Scalability_Reliability/concurrency_inventory.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/08_Scalability_Reliability/concurrency_inventory.md)). |
| **Assertion 2** | `available_stock >= 0` | Relational database schema constraint `CHECK(available_quantity >= 0)` ([`04_Database/schema.sql`](file:///f:/system%20design%20hack/SALESTORM_TEAM/04_Database/schema.sql)). |
| **Assertion 3** | `no duplicate reservations` | Redis `SETNX` customer key tracking `inv:cust:prod_X:cust_Y` ([`08_Scalability_Reliability/concurrency_inventory.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/08_Scalability_Reliability/concurrency_inventory.md)). |
| **Assertion 4** | `no duplicate payments` | Gateway Idempotency Guard checking `Idempotency-Key` headers ([`05_API/api_notes.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/05_API/api_notes.md)). |
| **Assertion 5** | `no duplicate orders` | DB-backed consumer idempotency via `processed_event` table ([`05_API/events.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/05_API/events.md)). |
| **Assertion 6** | `100% paid -> orders` | Transactional Outbox pattern & Kafka buffer durability during 30s outage ([`03_LLD/sequence_order_and_recovery.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/03_LLD/sequence_order_and_recovery.md)). |
| **Assertion 7** | `available + reserved + sold == 100` | Idempotent stock release & stock conservation state machine ([`03_LLD/state_reservation.md`](file:///f:/system%20design%20hack/SALESTORM_TEAM/03_LLD/state_reservation.md)). |
