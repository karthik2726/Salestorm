# SALESTORM: Design-First High-Scale Flash-Sale Architecture
## Hackathon Pitch Deck & System Architecture Executive Summary

---

## Slide 1: Executive Summary & System Identity
* **System Name:** SALESTORM
* **Domain:** High-Scale Flash-Sale E-Commerce Platform
* **Mission:** Architectural excellence under extreme concurrency (500,000 req/sec peak), guaranteeing **zero overselling**, **zero double-charging**, **zero duplicate orders**, and **100% resilience** during service outages.

---

## Slide 2: The Flash Sale Problem Statement
* **The Challenge:** Product X has exactly 100 units. 10,000 customers click "Buy Now" simultaneously at $t = 0.0\text{s}$.
* **The Failure Modes of Naïve Architectures:**
  * Direct SQL updates cause row lock contention $\rightarrow$ Connection pools crash within 500ms $\rightarrow$ HTTP 504 Gateway Timeouts.
  * Optimistic locking version checks cause 99% transaction aborts and retry storms.
  * Payment timeouts lead to double-charging cards or dropping orders.

---

## Slide 3: Architectural Solution Overview

```
[500k req/s Edge] ──> [WAF & Waiting Room] ──> [Redis Lua Gate] ──> [Postgres Outbox] ──> [Kafka] ──> [Order Svc]
```

1. **Edge Filter:** Cloudflare CDN WAF drops bots and short-circuits stock-depleted requests using distributed KV `SOLD_OUT` flags.
2. **Virtual Waiting Room:** Token-bucket queue controls ingress admission to 100 req/sec.
3. **Redis Atomic Gate:** Single-threaded Lua script reserves stock in $<1.5\text{ ms}$, eliminating DB lock contention completely.
4. **Transactional Outbox:** Decouples DB persistence from event publishing to Apache Kafka.
5. **Idempotent Consumers:** DB-backed `processed_event` ledger guarantees exactly-once order processing.

---

## Slide 4: Hybrid Inventory Lock Comparison

| Dimension | Optimistic Locking | Pessimistic Locking | Redis Atomic Lua Gate | **SALESTORM Hybrid** |
| :--- | :--- | :--- | :--- | :--- |
| **Max Throughput** | ~500 req/s | ~150 req/s | **> 100,000 req/s** | **> 100,000 req/s** |
| **Contention Behavior**| Retry storms | Connection crashes | Zero lock contention | Fast gate + Async DB |
| **Oversell Risk** | Zero | Zero | Zero | **Zero (Proven)** |

---

## Slide 5: Resilient Outage & Failure Recovery

* **Scenario: 30-Second Order Service Outage during Flash Sale**
  * 95 payments complete successfully.
  * Order Service pods crash for 30 seconds.
  * **Result:** Apache Kafka buffers `PaymentConfirmed` events safely in partition logs. Upon container recovery at $t = 35\text{s}$, Order Service processes all 95 orders idempotently with **zero message loss** and **zero customer drop**.

---

## Slide 6: Benchmark Metrics & Guarantees

* **Peak Edge Ingress:** 500,000 req/sec handled at Edge WAF.
* **Reservation Gate Latency:** p95 $<20\text{ ms}$, p99 $<50\text{ ms}$.
* **Availability Target:** 99.99% uptime (<52.6 min unexpected downtime/year).
* **Recovery Point Objective (RPO):** RPO = 0 for financial transactions (Synchronous WAL Aurora DB).
* **Recovery Time Objective (RTO):** RTO $<30\text{s}$ for database primary failover.

---

## Slide 7: Why SALESTORM Wins
1. **Design-First Rigor:** Full C4 Level 1-3 diagrams, OpenAPI 3 specs, PostgreSQL DDL, and state transition matrices.
2. **Mathematical Guarantees:** Proven non-oversale logic, idempotency guards, and circuit breaker resilience.
3. **Enterprise Code Quality:** 100% SOLID principle mapping and 8 design patterns applied cleanly.
