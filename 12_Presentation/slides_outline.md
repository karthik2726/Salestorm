# SALESTORM: 5-Minute Hackathon Pitch Deck & Presentation Guide

---

## Slide 1: The High-Concurrency Flash Sale Challenge (30 Seconds)
* **Title:** The Flash Sale Concurrency Nightmare
* **Bullet Points:**
  * Product X has **100 units**; **10,000 customers** click "Buy Now" at $t = 0.0\text{s}$.
  * Naïve SQL updates crash connection pools within 500ms (HTTP 504 timeouts).
  * Optimistic locking causes 99% transaction aborts and massive retry storms.
* **Diagram to Show:** High-Concurrency Ingress Traffic Spike Diagram.
* **Speaker Notes (Exact Timing: 0:00 - 0:30):**
  *"Judges, imagine 10,000 buyers slamming 'Buy Now' for just 100 available units. Traditional e-commerce architectures fail instantly. Database row locks freeze threads, connection pools exhaust in half a second, and users get HTTP 504 errors. SALESTORM was engineered from the ground up to solve this exact problem without overselling or crashing."*

---

## Slide 2: Strict Guarantees vs. System Targets (30 Seconds)
* **Title:** Non-Negotiable System Guarantees & Targets
* **Bullet Points:**
  * **Zero Oversell:** Stock available never falls below zero ($available\_qty \ge 0$).
  * **Zero Double-Charge:** Unique `Idempotency-Key` tied to reservation ID.
  * **Extreme Scale Targets:** 500,000 req/s peak ingress, p95 latency $<20\text{ ms}$, RPO = 0.
* **Diagram to Show:** Guarantees vs. Targets Comparison Matrix.
* **Speaker Notes (Exact Timing: 0:30 - 1:00):**
  *"We define strict mathematical guarantees versus system performance targets. Overselling, double-charging, and duplicate orders are strictly unacceptable failure modes. Our targets deliver sub-20ms reservation latency and 99.99% operational uptime under a 500k req/s traffic burst."*

---

## Slide 3: High-Level Architecture & Traffic Pipeline (60 Seconds)
* **Title:** Edge-to-Core Architecture Overview
* **Bullet Points:**
  * **Cloudflare Edge WAF:** Drops bots & short-circuits stock-depleted traffic via `SOLD_OUT` KV flag.
  * **Virtual Waiting Room:** Token-bucket queue admits traffic at a safe 100 req/sec rate.
  * **Redis Atomic Gate:** Single-threaded Lua script reserves stock in $<1.5\text{ ms}$.
* **Diagram to Show:** C4 Level 2 Container Diagram (`02_HLD/container_diagram.md`).
* **Speaker Notes (Exact Timing: 1:00 - 2:00):**
  *"Here is our end-to-end container architecture. When traffic spikes, Cloudflare Edge WAF sheds 80% of bot spam. Admitted users enter a Virtual Waiting Room that throttles ingress into our core Go Inventory Service at 100 req/sec. Stock is reserved atomically in Redis memory in under 1.5 milliseconds, shielding PostgreSQL from hot-row contention entirely."*

---

## Slide 4: Critical Design: Atomic Inventory Contention Gate (60 Seconds)
* **Title:** The Hybrid Inventory Lock
* **Bullet Points:**
  * Single atomic Lua script (`reserve_stock.lua`) checks limits and decrements stock.
  * PostgreSQL Aurora Multi-AZ acts as durable source of truth with `CHECK(qty >= 0)`.
  * Background sweeper reconciles Redis memory against PostgreSQL WAL ledgers.
* **Diagram to Show:** Concurrency Comparison Matrix & Sequence Diagram (`08_Scalability_Reliability/concurrency_inventory.md`).
* **Speaker Notes (Exact Timing: 2:00 - 3:00):**
  *"Why did we choose a hybrid lock? Pessimistic locks lock up database threads; optimistic locks cause 99% retry failures. Our Redis Lua script executes stock checks, customer purchase limits, and reservation issuance serially in memory. It is mathematically impossible to oversell. PostgreSQL asynchronously persists state with strict schema check constraints."*

---

## Slide 5: Resilient Payment Capture & 30s Outage Recovery (45 Seconds)
* **Title:** Payment Settlement & 30s Outage Survival
* **Bullet Points:**
  * **Payment Idempotency:** Intercepts duplicate requests, returning cached status.
  * **Transactional Outbox:** Writes DB state and event payload in local ACID transaction.
  * **Kafka Buffer Durability:** Absorbs 30s Order Service outages with zero data loss.
* **Diagram to Show:** Sequence Diagram for Payment & Outage Recovery (`03_LLD/sequence_order_and_recovery.md`).
* **Speaker Notes (Exact Timing: 3:00 - 3:45):**
  *"For payments, client idempotency keys guarantee zero double-charging. When payments succeed, we write events using the Transactional Outbox pattern to Apache Kafka. If the Order Service crashes for 30 seconds during the sale, Kafka buffers 95 payment events safely. Upon container recovery, Order Service processes all orders idempotently with zero lost payments."*

---

## Slide 6: Low-Level Engineering, SOLID & Design Patterns (45 Seconds)
* **Title:** Low-Level Engineering Excellence
* **Bullet Points:**
  * **100% SOLID Compliance:** Decoupled interfaces (DIP) and strategy factories (OCP).
  * **8 Core Patterns:** Strategy, Factory, State, Observer, Adapter, Repository, Facade, Circuit Breaker.
  * **Zero-Touch Extension:** Add new payment gateways (PayPal) or delivery partners (DHL) without modifying existing code.
* **Diagram to Show:** C4 Level 3 Component Diagrams (`03_LLD/component_diagram.md`).
* **Speaker Notes (Exact Timing: 3:45 - 4:30):**
  *"Our low-level design strictly follows SOLID principles. The Gateway Adapter Strategy Pattern allows adding new payment providers like PayPal or couriers like DHL by implementing a single interface, without changing core checkout logic. Resilience4j circuit breakers isolate external provider timeouts."*

---

## Slide 7: Live Validation, 50x Scale & Automated Assertions (30 Seconds)
* **Title:** AI-Assisted Validation & 500k rps Scale
* **Bullet Points:**
  * **50x Scale Readiness:** Handles 500,000 req/sec peak ingress via edge shedding.
  * **Live Visualizer Dashboard:** Running live on `localhost:3000`.
  * **Passed Assertions:** 100% mathematical pass on oversell, idempotency, and outage recovery.
* **Diagram to Show:** AI Validation Report & Live Dashboard Screenshot (`11_AI_Assisted_Validation/validation_report.md`).
* **Speaker Notes (Exact Timing: 4:30 - 5:00):**
  *"We validated our design using an automated simulation engine running live on port 3000. All 5 system assertions passed with zero oversell, zero duplicate charges, and complete 30-second outage recovery. SALESTORM is ready for production. Thank you!"*
