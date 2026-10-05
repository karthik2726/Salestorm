# C4 Level 3: Component Diagrams

This document details the internal software architecture for the three critical core microservices: **Inventory & Reservation Service**, **Payment Service**, and **Order Service**.

---

## 1. Inventory & Reservation Service (Component Diagram)

```mermaid
C4Component
    title Component Diagram: Inventory & Reservation Service (Go)

    Container(gateway, "API Gateway / Waiting Room", "Kong / Waiting Room Service")
    ContainerDb(redis, "Redis Cluster", "Redis 7.x")
    ContainerDb(postgres, "PostgreSQL Database", "Postgres 16")
    ContainerDb(kafka, "Apache Kafka", "Kafka 3.x")

    Container_Boundary(inv_svc_boundary, "Inventory & Reservation Service") {
        Component(res_controller, "Reservation Controller", "Go HTTP/gRPC Handler", "Validates payload schema, checks auth claims, and parses idempotency keys.")
        Component(admission_gate, "Admission Token Validator", "Go Module", "Verifies waiting-room cryptographic signatures before allowing reservation access.")
        Component(lua_engine, "Redis Lua Execution Engine", "Go Redis Client Wrapper", "Executes `reserve_stock.lua` atomically against Redis Cluster.")
        Component(reservation_dao, "Postgres Reservation DAO", "Go GORM / pgx", "Performs background asynchronous write-through of reservation records to PostgreSQL.")
        Component(sweeper_worker, "Reservation Expiry Sweeper", "Go Background Cron", "Scans expired reservations (TTL > 10m) and releases inventory back to Redis/DB.")
        Component(outbox_pub, "Inventory Outbox Publisher", "Go Kafka Producer", "Writes `ReservationCreated` events to transactional outbox and pushes to Kafka.")
    }

    Rel(gateway, res_controller, "POST /api/v1/reservations", "gRPC / HTTP")
    Rel(res_controller, admission_gate, "Validate Ticket Token", "In-Memory Call")
    Rel(admission_gate, lua_engine, "Execute Reserve Stock", "In-Memory Call")
    Rel(lua_engine, redis, "EVALSHA reserve_stock.lua", "RESP Protocol")
    Rel(lua_engine, reservation_dao, "Queue Async Persistence", "Go Channel")
    Rel(reservation_dao, postgres, "INSERT INTO reservations / UPDATE inventory", "SQL")
    Rel(sweeper_worker, redis, "Release Expired Stock Token", "RESP")
    Rel(sweeper_worker, postgres, "UPDATE reservations SET status='RELEASED'", "SQL")
    Rel(lua_engine, outbox_pub, "Emit Event", "Go Channel")
    Rel(outbox_pub, kafka, "Publish to `inventory-events` topic", "Kafka Protocol")
```

### Component Breakdown: Inventory & Reservation Service
1. **Reservation Controller:** Exposes gRPC and REST endpoints. Responsible for input validation, sanitization, and request routing.
2. **Admission Token Validator:** Decrypts and validates token bucket signatures issued by the Virtual Waiting Room to prevent unauthorized direct API bypasses.
3. **Redis Lua Execution Engine:** Wraps the Redis client library. Invokes the atomic reservation script (`reserve_stock.lua`) which verifies customer purchase limits, stock balance, and idempotency in a single single-threaded Redis execution thread.
4. **Postgres Reservation DAO:** Handles durable persistence in PostgreSQL asynchronously via worker channels, maintaining the transactional outbox table.
5. **Reservation Expiry Sweeper:** Scheduled daemon that queries PostgreSQL for reservations where `status = 'RESERVED'` and `expires_at < NOW()`, triggering idempotent stock replenishment.

---

## 2. Payment Service (Component Diagram)

```mermaid
C4Component
    title Component Diagram: Payment Service (Java / Spring Boot)

    Container(chk_svc, "Checkout Service", "Go Microservice")
    Container(payment_gw, "External Payment Gateway", "Stripe / Adyen REST API")
    ContainerDb(postgres, "PostgreSQL Database", "Postgres 16")
    ContainerDb(kafka, "Apache Kafka", "Kafka 3.x")

    Container_Boundary(pay_svc_boundary, "Payment Service") {
        Component(pay_controller, "Payment Controller", "Spring MVC Controller", "Accepts payment initiation requests bound to a `reservation_id`.")
        Component(idempotency_guard, "Idempotency Enforcer", "Spring Aspect / Redis Filter", "Checks `idempotency_key` in Redis/DB to block duplicate payment execution.")
        Component(gw_adapter_mgr, "Gateway Adapter Manager", "Spring Service", "Selects and executes external payment gateway integration adapters (Stripe/Adyen).")
        Component(circuit_breaker, "Circuit Breaker Resilience Manager", "Resilience4j", "Wraps gateway HTTP calls with timeouts, bulkheads, and fallback circuit open logic.")
        Component(webhook_receiver, "Webhook Ingestion Handler", "Spring Controller", "Processes asynchronous webhooks from payment gateways for pending/unknown charges.")
        Component(reconciler, "Payment Reconciliation Engine", "Scheduled Task", "Queries gateway status API for transactions stuck in `PAYMENT_UNKNOWN` state.")
        Component(pay_outbox, "Payment Outbox Publisher", "Spring Kafka Producer", "Writes `PaymentConfirmed` or `PaymentFailed` events to outbox for Kafka delivery.")
    }

    Rel(chk_svc, pay_controller, "POST /api/v1/payments", "HTTPS / gRPC")
    Rel(pay_controller, idempotency_guard, "Check Duplicate Key", "Internal Call")
    Rel(idempotency_guard, gw_adapter_mgr, "Delegate Execution", "Internal Call")
    Rel(gw_adapter_mgr, circuit_breaker, "Execute Charge", "Internal Call")
    Rel(circuit_breaker, payment_gw, "POST /v1/charges", "HTTPS REST API")
    Rel(payment_gw, webhook_receiver, "POST /api/v1/payments/webhook", "Async HTTPS")
    Rel(reconciler, payment_gw, "GET /v1/charges/{id}", "HTTPS REST API")
    Rel(gw_adapter_mgr, pay_outbox, "Save State & Publish", "Transactional Boundary")
    Rel(pay_outbox, postgres, "INSERT INTO payment_outbox", "SQL")
    Rel(pay_outbox, kafka, "Publish to `payment-events` topic", "Kafka Protocol")
```

### Component Breakdown: Payment Service
1. **Payment Controller:** Validates payment request schemas and client-generated idempotency keys.
2. **Idempotency Enforcer:** Intercepts payment invocations. If an `idempotency_key` has already been processed or is currently executing, it blocks redundant calls and returns the cached payment status.
3. **Gateway Adapter Manager:** Abstract strategy pattern facilitating runtime switching between primary (Stripe) and secondary (Adyen) payment processors.
4. **Circuit Breaker Resilience Manager:** Utilizes Resilience4j to enforce a strict 2,000ms SLA timeout. If gateway error rates exceed 50%, it trips open to prevent resource thread exhaustion.
5. **Payment Reconciliation Engine:** Polling engine that periodically inspects transactions in `PAYMENT_UNKNOWN` state, querying the external provider to resolve final payment state.

---

## 3. Order Service (Component Diagram)

```mermaid
C4Component
    title Component Diagram: Order Service (Java / Spring Boot)

    ContainerDb(kafka, "Apache Kafka", "Kafka 3.x")
    ContainerDb(postgres, "PostgreSQL Database", "Postgres 16")
    Container(ship_svc, "Shipment Service", "Go Service")

    Container_Boundary(ord_svc_boundary, "Order Service") {
        Component(kafka_consumer, "Payment Event Consumer", "Spring Kafka Listener", "Subscribes to `payment-events` topic with batch concurrency.")
        Component(idempotent_proc, "Idempotent Event Processor", "Spring Component", "Queries `processed_events` table before processing incoming events.")
        Component(order_state_engine, "Order State Machine Engine", "Spring StateMachine", "Manages state transitions (`CREATED` -> `CONFIRMED` -> `PROCESSING`).")
        Component(order_dao, "Order Database DAO", "Spring Data JPA", "Persists order records, line items, and audit logs to PostgreSQL.")
        Component(saga_compensator, "Saga Compensation Handler", "Spring Component", "Issues refund and stock release events if downstream order creation fails.")
    }

    Rel(kafka, kafka_consumer, "Consume `PaymentConfirmed` Event", "Kafka Protocol")
    Rel(kafka_consumer, idempotent_proc, "Process Event Payload", "Internal Call")
    Rel(idempotent_proc, postgres, "SELECT / INSERT `processed_events`", "SQL")
    Rel(idempotent_proc, order_state_engine, "Trigger State Transition", "Internal Call")
    Rel(order_state_engine, order_dao, "Save State", "Internal Call")
    Rel(order_dao, postgres, "INSERT INTO orders / order_items", "SQL")
    Rel(order_state_engine, saga_compensator, "Trigger Compensation on Error", "Internal Call")
    Rel(saga_compensator, kafka, "Publish `OrderFailed` / Refund Event", "Kafka Protocol")
```

### Component Breakdown: Order Service
1. **Payment Event Consumer:** High-throughput Kafka consumer configured with manual acknowledgement offsets and retry topics.
2. **Idempotent Event Processor:** Checks incoming Kafka message UUIDs against the `processed_events` database table. If already present, skips execution and commits offset to prevent duplicate orders.
3. **Order State Machine Engine:** Enforces explicit state transition logic (`CREATED` $\rightarrow$ `PAYMENT_PENDING` $\rightarrow$ `CONFIRMED` $\rightarrow$ `PROCESSING` $\rightarrow$ `SHIPPED`).
4. **Saga Compensation Handler:** Triggers compensation actions (initiating Stripe refunds and dispatching inventory releases) if order creation encounters fatal database errors or business constraint violations.

---

## Architectural Trade-Offs Across Components

1. **Transactional Outbox vs Direct Dual Write:**
   * *Trade-off:* Microservices write events to an in-database `outbox` table first before a background process pushes to Kafka, introducing a ~50ms event dispatch lag.
   * *Justification:* Guarantees atomic database updates and event publishing. Eliminates silent state divergence where a DB write succeeds but network failure drops the Kafka event.
2. **Database-backed Idempotency Checking:**
   * *Trade-off:* Requires a primary key lookup in `processed_events` for every consumed Kafka event.
   * *Justification:* Absolutely mandatory for financial correctness. Guarantees exactly-once order creation even during network partitions, consumer crashes, or Kafka partition rebalances.
