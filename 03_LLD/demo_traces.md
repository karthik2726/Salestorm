# SALESTORM System Demo Traces & Test Case Validation

This document provides complete step-by-step trace logs and behavioral validations for the 7 primary practical test scenarios.

---

## Trace Scenario 1: One Successful Purchase Lifecycle

```
[User App] ──> (1) POST /v1/reservations ──> [API Gateway] ──> (2) Lua EVALSHA ──> [Redis (Stock: 100->99)]
                                                                                       │
[User App] <── (5) 200 OK (Confirmed) <── [Order Svc] <── (4) Kafka Event <── (3) POST /v1/payments ──┘
```

1. **User Request:** User `cust_101` clicks "Buy Now" for `prod_flash_x` ($Stock = 100$). Request includes `Idempotency-Key: idemp_seq_101`.
2. **Admission & Lua Execution:** API Gateway validates JWT. Ingested by Inventory Service, executing Redis Lua script (`reserve_stock.lua`). Redis decrements stock ($100 \rightarrow 99$), sets customer key `inv:cust:prod_flash_x:cust_101`, and returns `reservation_id_991` with a 10-minute TTL.
3. **Outbox Persistence:** Inventory Service writes `inventory_reservation` record ($status = 'RESERVED'$) and `outbox_event` payload in a single PostgreSQL transaction (`Tx-1`).
4. **Checkout & Payment:** User submits `POST /v1/payments` with `reservation_id_991` and `Idempotency-Key: pay_seq_101`. Payment Service charges card via Stripe Gateway Adapter. Stripe returns `200 OK` ($transaction\_ref = 'tx_stripe_991'$).
5. **Event Emission & Order Creation:** Payment Service writes `payment` record ($status = 'SUCCESS'$) and publishes `PaymentConfirmed` event to Kafka topic `payment-events`. Order Service consumes event, verifies `processed_event` table, inserts order record ($status = 'CONFIRMED'$), and emits `OrderConfirmed` event. User UI updates to "Order Confirmed".

---

## Trace Scenario 2: Failed Payment & Idempotent Stock Release

1. **Reservation:** User `cust_102` successfully reserves stock ($reservation\_id\_992$, $Stock = 99 \rightarrow 98$).
2. **Payment Attempt:** User submits payment. Payment Service invokes Stripe API. Stripe rejects card with `402 Card Declined` (insufficient funds).
3. **State Transition & Event Dispatch:** Payment Service updates payment record to `FAILED` and publishes `PaymentFailed` event to Kafka topic `payment-events`.
4. **Idempotent Stock Replenishment:** Inventory Service consumes `PaymentFailed` event and executes idempotent stock release Lua script:
   * Redis executes: `INCRBY inv:stock:prod_flash_x 1` ($Stock = 98 \rightarrow 99$).
   * Redis deletes customer limit key `inv:cust:prod_flash_x:cust_102`.
   * PostgreSQL updates reservation status to `RELEASED`. Stock is now available for other buyers in the queue.

---

## Trace Scenario 3: Duplicate Buy Request (Idempotency Key Protection)

1. **Initial Request:** User `cust_103` clicks "Buy Now". Request `POST /v1/reservations` arrives with `Idempotency-Key: idemp_dup_88`.
2. **First Execution:** Redis Lua script executes, reserves stock, and caches the response:
   `SET inv:idemp:idemp_dup_88 reservation_id_993 EX 600`. Returns `HTTP 201 Created`.
3. **Duplicate Arrival:** Due to a mobile network retry, an identical `POST /v1/reservations` request with `Idempotency-Key: idemp_dup_88` hits the API Gateway 200ms later.
4. **Idempotency Guard Interception:** Redis Lua script checks `EXISTS inv:idemp:idemp_dup_88`.
5. **Result:** Lua script detects existing key and immediately returns `{ "ALREADY_PROCESSED", "reservation_id_993" }`. The service returns the original `HTTP 201 Created` response without re-decrementing stock. Zero double-reservation occurs.

---

## Trace Scenario 4: Payment Success + Order Service 30-Second Outage Recovery

1. **Payment Capture:** User `cust_104` completes payment ($payment\_id\_44$). Payment Service writes `PaymentConfirmed` event to Kafka topic `payment-events`.
2. **Container Failure ($t = 0s$):** All Order Service Kubernetes pods crash due to an out-of-memory error.
3. **Durable Kafka Buffering ($t = 0s \rightarrow 30s$):** Kafka retains the `PaymentConfirmed` message safely in the partition log. Client app displays "Payment Received - Confirming Order".
4. **Container Recovery ($t = 30s$):** Kubernetes Kubelet restarts Order Service pods. Pods reconnect to Kafka brokers and resume polling.
5. **Idempotent Order Creation ($t = 31s$):** Order Service consumes `PaymentConfirmed` event, verifies `processed_event` table, creates order record ($status = 'CONFIRMED'$), and commits Kafka offset. Order status transitions to "Confirmed" with zero data loss.

---

## Trace Scenario 5: Inventory Reaching Zero & Edge Short-Circuiting

1. **Final Unit Reservation:** Stock counter in Redis reaches $1$. User `cust_100` reserves final unit ($Stock = 1 \rightarrow 0$).
2. **Edge Event Propagation:** Redis Lua script detects $Stock = 0$. Inventory Service publishes an `InventoryDepleted` event to Kafka.
3. **CDN Flag Update:** A background worker updates Cloudflare Worker KV store: `SET SOLD_OUT_prod_flash_x true`.
4. **Subsequent Ingress Rejection:** The remaining $9,900$ buyers in the waiting room attempt to submit reservations.
5. **Edge Short-Circuiting:** Cloudflare Edge WAF intercepts requests, checks `SOLD_OUT == true`, and immediately returns static `HTTP 200 "Sold Out"` responses. Core microservices and databases receive 0 requests post-depletion.

---

## Trace Scenario 6: 50x Traffic Burst Handling (500,000 req/sec Peak)

1. **Ingress Spike:** Flash sale launches. Global ingress spikes to $500,000\text{ req/sec}$ across Anycast edge nodes.
2. **Layer 1 (Edge WAF):** Cloudflare DDoS rules drop $400,000\text{ req/sec}$ of automated bot scripts and duplicate IP spam ($80\%$ load shed).
3. **Layer 2 (API Gateway Rate Limiting):** Kong API Gateway enforces per-user IP rate limits using Redis token buckets, shedding an additional $90,000\text{ req/sec}$ with `HTTP 429 Too Many Requests`.
4. **Layer 3 (Virtual Waiting Room):** The remaining $10,000\text{ req/sec}$ enter the Virtual Waiting Room, which throttles admission to the core Inventory Service at a strict rate of $100\text{ req/sec}$. Core infrastructure operates smoothly under normal capacity limits.

---

## Trace Scenario 7: Multi-Layer Fault Recovery (Database & Payment Gateway Failures)

```
[Stripe Gateway Failure] ──> Circuit Breaker TRIPS OPEN ──> HTTP 503 (Graceful Retry)
[DB Primary Failover]   ──> RDS Multi-AZ Failover    ──> RTO < 30s (WAL Replicated)
```

1. **Payment Gateway Outage:** Stripe API starts returning 5xx server errors and times out (>2000ms).
   * **Circuit Breaker Action:** Resilience4j monitors error rate. When error rate exceeds 50%, Circuit Breaker trips to `OPEN` state.
   * **Fallback Handling:** Payment Service short-circuits subsequent payment requests, immediately returning `HTTP 503 Service Unavailable` with `Retry-After: 10`. Card charge calls are suspended, protecting gateway thread pools.
2. **Database Primary Node Failure:** PostgreSQL Primary instance suffers hardware failure in `us-east-1a`.
   * **RDS Failover Action:** AWS RDS detects lost heartbeat and automatically promotes the Multi-AZ synchronous Read Replica in `us-east-1b` to Primary Writer.
   * **Application Re-connection:** HikariCP connection pool drops dead connections and reconnects to new Primary Writer endpoint within $<30\text{ seconds}$. Zero data loss occurs ($RPO = 0$).

---

## Architectural Trade-Offs

* **Edge Short-Circuiting Lag:**
  * *Trade-off:* Updating Cloudflare KV store takes ~100-200ms, during which a few requests might still reach the Redis gate after stock hits 0.
  * *Justification:* Redis Lua gate safely rejects these excess requests with HTTP 409, maintaining 100% stock accuracy.
