# Hackathon Jury Q&A Defense Guide

This document provides crisp, architecturally rigorous 3-to-5 sentence answers to the 10 most critical jury defense questions.

---

### Q1: Why is this the right service boundary?
**Answer:** We separated Inventory, Checkout, Payment, and Order into discrete microservices based on domain volatility and isolation requirements. Payment processing depends on unpredictable 3rd-party gateway latencies (500-2000ms), while Inventory reservation requires ultra-fast sub-20ms memory operations. Isolating these domains prevents slow payment calls or courier logistics failures from starving CPU threads of the high-speed Inventory gate.

---

### Q2: Where exactly is inventory consistency guaranteed?
**Answer:** Inventory consistency is guaranteed at two layers. First, the in-memory gate executes a single-threaded atomic Redis Lua script (`reserve_stock.lua`) that checks stock and customer limits sequentially in $<1.5\text{ ms}$. Second, the authoritative PostgreSQL database enforces a hard relational schema constraint: `CHECK(available_quantity >= 0)` alongside conditional updates (`WHERE available_quantity >= req_qty`).

---

### Q3: What happens if two requests hit the inventory service at the same time?
**Answer:** Redis processes network requests in a single-threaded event loop engine. When two requests arrive simultaneously for the final stock unit ($Stock = 1$), Redis executes the first Lua script completely—decrementing stock to 0 and issuing a reservation token—before opening the second request. The second request evaluates $Stock = 0$ and immediately returns an HTTP 409 `OUT_OF_STOCK` response.

---

### Q4: Why this concurrency strategy over optimistic or pessimistic locking?
**Answer:** Pessimistic locking (`SELECT FOR UPDATE`) forces 10,000 requests to block sequentially on a single database row lock, crashing connection pools within 500ms. Optimistic locking (`version` column) causes 9,900 requests (99%) to fail version verification, creating severe retry storms that overwhelm application servers. Our hybrid model uses Redis memory for fast, zero-contention gatekeeping, backed by PostgreSQL for durable ACID outbox updates.

---

### Q5: Why is this operation synchronous and that one asynchronous?
**Answer:** Inventory reservation and payment authorization are synchronous because the buyer requires immediate deterministic feedback on stock allocation and credit card authorization before checkout expires. Downstream order creation, warehouse fulfillment, shipping label generation, and notifications are asynchronous via Apache Kafka. This decouples core checkout from downstream services, allowing the platform to absorb service outages without dropping transactions.

---

### Q6: How do we recover from payment success then order failure?
**Answer:** When payment succeeds, the Payment Service writes a `PaymentConfirmed` event to Kafka via the Transactional Outbox pattern. If order creation subsequently fails due to fatal business constraint violations, the Order Service triggers an automated **Saga Compensation Workflow**. This publishes a `RefundInitiated` event to Stripe and an `InventoryReleaseRequested` event to Redis, returning funds to the buyer and restoring stock atomically.

---

### Q7: Which component is the bottleneck and how does it scale?
**Answer:** The primary core bottleneck is external Payment Gateway API rate limits (typically 100-500 req/sec per API key) and network latency. We scale and protect this bottleneck using the Virtual Waiting Room to throttle payment admission flow to match gateway quotas. Internally, microservice pods scale horizontally via Kubernetes HPA based on CPU and request queue depth, while PostgreSQL read queries scale via Aurora Read Replicas.

---

### Q8: What happens if the DB primary or payment gateway fails?
**Answer:** If the PostgreSQL Primary crashes, AWS RDS Multi-AZ automatically promotes the synchronous Read Replica to Primary in $<30\text{ seconds}$ with zero data loss ($RPO = 0$). If the payment gateway times out or fails, Resilience4j Circuit Breakers trip to `OPEN` state after a 50% failure rate, short-circuiting calls with HTTP 503 fallback. Indeterminate transactions enter `PAYMENT_UNKNOWN` and are resolved safely by background reconciliation polling.

---

### Q9: What changes at 50x traffic (500,000 req/sec peak)?
**Answer:** At 50x scale, Anycast Cloudflare Edge WAF sheds 400,000 req/sec (80%) of bot scripts and duplicate IP spam. Kong API Gateway rate-limiters shed an additional 90,000 req/sec (HTTP 429), and the Virtual Waiting Room throttles admission to the core Inventory Service at a strict 100 req/sec. The first component to saturate is the Gateway Redis rate-limiting node, which is mitigated by moving rate limits directly to Cloudflare Workers at the edge.

---

### Q10: "100 units left, 10,000 customers click Buy Now. Walk us through exactly what happens until final orders are confirmed."
**Answer:**
1. At $t = 0.0\text{s}$, 10,000 requests hit Cloudflare Edge. 9,900 enter the Virtual Waiting Room with HTTP 202 status and poll tickets; 100 requests are admitted to the Inventory Service.
2. The 100 admitted requests execute the atomic Redis Lua script (`reserve_stock.lua`). Exactly 100 reservations succeed; stock balance drops to 0. Redis emits an event setting Cloudflare Edge KV flag `SOLD_OUT = true`, which immediately returns HTTP 200 "Sold Out" to all remaining 9,900 waiting buyers.
3. The 100 reserved users proceed to `/v1/payments` with unique `Idempotency-Key` headers. 95 payments succeed; 5 fail due to card declines. The 5 declined payments trigger an idempotent Lua release script returning 5 units to stock for queue backfill.
4. The 95 successful payments write `PaymentConfirmed` events to Kafka via Transactional Outbox. Even if the Order Service experiences a 30-second outage, Kafka buffers all 95 events. Upon recovery, Order Service checks the `processed_event` table, inserts 95 orders, and updates status to `CONFIRMED` with zero data loss.
