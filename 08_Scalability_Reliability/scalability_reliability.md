# System Scalability, Reliability & Fault-Tolerance Engineering

This document provides a comprehensive analysis of horizontal scaling, state management, caching topologies, queue backpressure, database sharding, resilience policies, failure scenario runbooks, and trade-offs for SALESTORM.

---

## 1. Horizontal Scaling & Service State Management

```
[Stateless Compute Layer]                 [Stateful Infrastructure Layer]
Kong API Gateway Pods  (HPA: CPU/Req) ──> Redis Cluster (Sharded by product_id)
Inventory Service Pods (HPA: Req Rate)──> PostgreSQL Aurora (1 Writer + Replicas)
Payment Service Pods   (HPA: Thread Pool) Kafka Brokers (MSK 32 Partitions)
Order Service Pods     (HPA: Queue Depth)
```

| Microservice | Scaling Strategy | Scaling Trigger Metric | State Location | Statelessness Justification |
| :--- | :--- | :--- | :--- | :--- |
| **API Gateway** | Kubernetes HPA (Autoscaling) | CPU Utilization > 70% | None (Stateless) | Validates JWTs statelessly using public key; zero session stickiness required. |
| **Virtual Waiting Room**| Kubernetes HPA | Ingress Queue Size > 5,000 | Redis Cluster | Queue positions and tokens stored in Redis memory; compute pods hold no local state. |
| **Inventory Service** | Kubernetes HPA | Requests/sec > 5,000/pod | Redis + PostgreSQL | Offloads all inventory counters to Redis; local pod memory is strictly ephemeral. |
| **Payment Service** | Kubernetes HPA | Connection Pool Usage > 80% | External Gateway + DB | Relies on client `Idempotency-Key` headers stored in Redis/DB. |
| **Order Service** | Kubernetes HPA | Kafka Partition Lag > 1,000 | PostgreSQL + Kafka | Idempotent consumers pull state from Kafka; order state persisted to PostgreSQL. |

---

## 2. Multi-Tier Caching Strategy

```
[User App] ──> (1) CDN Edge Cache (Static Assets & SOLD_OUT KV Flag)
                     │
                     └──(2) API Gateway Redis Cache (JWT Public Keys & Rate Limit Counters)
                              │
                              └──(3) Core Inventory Redis Cluster (Active Stock Counters & Lua Keys)
```

1. **CDN Edge Caching (Cloudflare Enterprise):**
   * **Cached Assets:** Static sale page HTML, CSS, product images, catalog metadata.
   * **Edge Flag (`SOLD_OUT`):** Cloudflare Worker KV flag. Set to `true` when Redis stock reaches 0. Rejects subsequent requests within $<10\text{ ms}$ at edge.
2. **Gateway Redis Cache:**
   * **Cached Data:** Public JWT verification keys, token-bucket IP rate limit counters, user session metadata.
3. **Core Redis Cluster:**
   * **Cached Data:** Inventory balance keys (`inv:stock:prod_X`), customer purchasing limit flags (`inv:cust:prod_X:user_Y`), idempotency keys (`inv:idemp:req_Z`).
   * **Invalidation Policy:** Explicit event-driven invalidation. Stock is decremented via Lua; stock releases explicitly increment keys (`INCRBY`).

---

## 3. Queueing, Backpressure & Consumer Scaling

* **Ingress Backpressure (Virtual Waiting Room):**
  * Implements a **Leaky Bucket / Token Bucket** algorithm. Enforces a maximum backend admission rate of $100\text{ req/sec}$, holding excess users in a virtual queue with polling status endpoints.
* **Event Stream Partitioning (Apache Kafka):**
  * Topics `inventory-events`, `payment-events`, and `order-events` are configured with **32 partitions** keyed by `product_id` or `reservation_id`.
  * **Consumer Scaling:** Up to 32 parallel Order Service consumer pod instances process events concurrently without partition lock contention.

---

## 4. Database Scaling & Hot-Row Protection

* **Partitioning & Sharding Strategy:**
  * PostgreSQL tables (`inventory_reservation`, `orders`, `payment`) are partitioned logically by `product_id` or `sale_id` using PostgreSQL declarative table partitioning.
* **Read Replicas & Connection Pooling:**
  * Read queries (product catalog browsing, order history) are routed to 2 Aurora Read Replicas.
  * **PgBouncer** connection poolers maintain a maximum of 500 active physical database connections, preventing thread exhaustion.
* **The Hot-Row Contention Problem & Redis Gate Protection:**
  * *Problem:* A flash sale concentrates 10,000 concurrent writes onto a single database row (`product_id = X`). Database row-level locks force sequential processing, exhausting connection pools.
  * *Protection:* The Redis atomic Lua gate intercepts 100% of concurrency in memory ($<1.5\text{ ms}$). PostgreSQL receives asynchronous, non-contended outbox updates, shielding the database from the hot-row lock problem.

---

## 5. 50x Traffic Burst Analysis (10,000 $\rightarrow$ 500,000 req/sec)

### Concrete Traffic Breakdown at 50x Ingress
* **Ingress Rate:** 500,000 req/sec.
* **Edge WAF Shedding:** 400,000 req/sec dropped (DDoS, malicious bots, spam IPs).
* **API Gateway Throttling:** 90,000 req/sec rate-limited (HTTP 429 Too Many Requests).
* **Admitted Traffic to Backend:** Throttled by Waiting Room to 100 req/sec.

### The First Component to Break & Mitigation
* **First Failure Point:** **API Gateway Redis Cluster Memory / Connection Limits.** Under 500,000 req/sec ingress, checking IP rate limit keys in Redis can saturate network interfaces.
* **Mitigation:** Enable Cloudflare Edge Rate Limiting to enforce rate limits directly at the edge before hitting the API Gateway.

---

## 6. Dependency Timeout, Retry, Backoff & Jitter Matrix

| Dependency Call | Timeout (SLA) | Max Retries | Backoff Strategy | Jitter Policy |
| :--- | :--- | :--- | :--- | :--- |
| **Gateway $\rightarrow$ Waiting Room** | 50 ms | 2 | Exponential ($10\text{ms}, 20\text{ms}$) | Full Jitter ($\pm 50\%$) |
| **Waiting Room $\rightarrow$ Inventory Svc**| 100 ms | 1 | No Retry (Immediate 429) | None |
| **Inventory Svc $\rightarrow$ Redis** | 15 ms | 2 | Linear ($5\text{ms}, 10\text{ms}$) | Equal Jitter |
| **Checkout Svc $\rightarrow$ Payment Svc** | 2,000 ms | 2 | Exponential ($500\text{ms}, 1000\text{ms}$)| Full Jitter |
| **Payment Svc $\rightarrow$ Stripe API** | 1,500 ms | 1 | No Retry (Move to `UNKNOWN`)| None |
| **Kafka Outbox Scraper** | 500 ms | 5 | Exponential ($100\text{ms} \rightarrow 1600\text{ms}$)| Full Jitter |

---

## 7. Circuit Breaker Settings (Payment Gateway)

Configured using Resilience4j:

* **Sliding Window Size:** 100 requests.
* **Failure Rate Threshold:** $50\%$ (if 50 out of 100 requests fail or time out, circuit trips).
* **Slow Call Rate Threshold:** $50\%$ (calls taking $> 1,500\text{ ms}$).
* **Wait Duration in Open State:** 10 seconds.
* **Half-Open State Behavior:** Admits 10 trial requests. If $\ge 90\%$ succeed, circuit transitions to `CLOSED`; otherwise, reverts to `OPEN`.
* **Fallback Behavior:** Immediately returns `HTTP 503 Service Unavailable` with header `Retry-After: 10`, preventing external API call stack buildup.

---

## 8. Dead-Letter Queue (DLQ) & Replay Procedure

1. **DLQ Routing:** Unprocessable messages in `payment-events` or `order-events` (e.g. schema parse errors, corrupted payloads) are routed to topic `order-events-dlq` after 3 failed retries.
2. **Monitoring & Alert:** Prometheus alert `DLQNonEmptyAlert` fires immediately to PagerDuty.
3. **Replay Procedure:**
   * Engineers inspect message payloads via the Ops Control CLI.
   * After resolving schema or system errors, execute the automated replay tool:
     ```bash
     kafka-dlq-replay --source-topic order-events-dlq --target-topic order-events --re-inject
     ```

---

## 9. Failure Scenarios Runbook

| Failure Scenario | Detection Mechanism | Automated Recovery & Runbook Steps |
| :--- | :--- | :--- |
| **PostgreSQL Primary Crash** | AWS RDS Health Check / Lost Heartbeat | Multi-AZ replica promoted to Primary in $<30\text{s}$ ($RTO < 30\text{s}$, $RPO = 0$). Applications reconnect automatically via Aurora cluster endpoint. |
| **Redis Node Loss** | Redis Sentinel / Cluster Manager | Promotes replica to master automatically ($<5\text{s}$). If data lost, triggers Cache Hydration Script from PostgreSQL. |
| **Payment Gateway Outage** | Circuit Breaker trips to `OPEN` | Payment Service short-circuits calls (HTTP 503). Reconciliation engine resolves pending charges when gateway recovers. |
| **Kafka Consumer Lag** | Prometheus metric `kafka_consumergroup_lag > 5000` | Kubernetes HPA scales Order Service consumer pods from 4 to 32 instances. |
| **Order Service Down 30s** | Container crash / Kubernetes Health Check fail | Kafka buffers `PaymentConfirmed` events durably. Order Service recovers, checks `processed_event` table, and processes orders with 0 data loss. |

---

## 10. Architectural Trade-Offs

* **Eventual Consistency vs Immediate Consistency:**
  * *Sacrifice:* Order confirmation UI relies on asynchronous Kafka event processing, introducing a 1-2 second status update window.
  * *Justification:* Necessary to decouple Payment Service from Order Service, allowing the platform to absorb complete Order Service outages without dropping transactions.
