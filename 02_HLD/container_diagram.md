# C4 Level 2: Container Diagram

The Container diagram illustrates the high-level technical architecture of SALESTORM, depicting microservices, datastores, event buses, and communication boundaries.

```mermaid
C4Container
    title Container Diagram for SALESTORM Flash-Sale Platform

    Person(customer, "Customer", "Browses sale items and purchases Product X")

    Container_Boundary(edge_layer, "Edge & Ingress Layer") {
        Container(cdn, "CDN & Edge WAF", "Cloudflare Enterprise", "Caches static sale pages, enforces DDoS protection, and blocks requests via SOLD_OUT edge flag.")
        Container(gateway, "API Gateway & Rate Limiter", "Kong / Envoy", "Handles AuthN (JWT validation), TLS termination, IP/user rate limiting, and routes traffic.")
    }

    Container_Boundary(microservices, "Core Microservices Tier") {
        Container(waiting_room, "Virtual Waiting Room", "Node.js / Go", "Queues excessive user requests, issuing rate-limited admission tokens (Token Bucket).")
        Container(prod_svc, "Product Catalog Service", "Go", "Manages product descriptions, pricing, and category metadata.")
        Container(cart_svc, "Cart Service", "Node.js", "Manages transient user cart items and checkout token signatures.")
        Container(inv_svc, "Inventory & Reservation Service", "Go", "Executes atomic inventory reservations via Redis Lua scripts and PostgreSQL sync.")
        Container(chk_svc, "Checkout Service", "Go", "Orchestrates checkout session initiation and ties reservation to payment payload.")
        Container(pay_svc, "Payment Service", "Java / Spring Boot", "Manages payment execution, gateway adapters, idempotency, and circuit breakers.")
        Container(ord_svc, "Order Service", "Java / Spring Boot", "Processes order state machine, consumer idempotency, and saga compensations.")
        Container(ship_svc, "Shipment Service", "Go", "Manages fulfillment dispatch, courier label creation, and tracking webhooks.")
        Container(notif_svc, "Notification Service", "Node.js", "Consumes Kafka events to send async emails/SMS messages.")
    }

    Container_Boundary(datastores, "Data & Event Streaming Tier") {
        ContainerDb(redis, "Redis Cluster", "Redis 7.x Cluster", "Stores rate limits, waiting room tokens, active inventory counters, and Lua idempotency keys.")
        ContainerDb(postgres, "PostgreSQL Primary & Replicas", "PostgreSQL 16", "Durable storage for inventory balances, reservations, payments, and order state machines.")
        ContainerDb(kafka, "Apache Kafka", "Kafka 3.x", "Event streaming platform providing Transactional Outbox queues and async decoupled topics.")
        ContainerDb(elastic, "Elasticsearch", "Elasticsearch 8.x", "Powers high-speed full-text product search and analytics queries.")
    }

    System_Ext(payment_gw, "Payment Gateway", "Stripe / Adyen")
    System_Ext(courier_sys, "Courier Logistics API", "FedEx / DHL")
    System_Ext(notif_gw, "SMS / Email Gateway", "Twilio / SendGrid")

    Rel(customer, cdn, "1. Accesses Sale Page / Clicks Buy", "HTTPS")
    Rel(cdn, gateway, "2. Proxies Authorized Requests", "HTTPS / gRPC")
    Rel(gateway, waiting_room, "3. Enforces Rate Admission", "HTTP / REST")
    Rel(waiting_room, inv_svc, "4. Passes Admitted User Request", "gRPC")
    Rel(inv_svc, redis, "5. Atomic Stock Check & Reserve", "RESP (Lua Script)")
    Rel(inv_svc, postgres, "6. Async Async Outbox/DB Sync", "SQL")
    Rel(inv_svc, kafka, "7. Publishes InventoryReserved Event", "Kafka Protocol")
    
    Rel(chk_svc, pay_svc, "8. Triggers Payment Execution", "gRPC / Sync REST")
    Rel(pay_svc, payment_gw, "9. Executes Credit Card Charge", "HTTPS API")
    Rel(pay_svc, kafka, "10. Publishes PaymentConfirmed Event", "Kafka Outbox")

    Rel(kafka, ord_svc, "11. Consumes PaymentConfirmed Event", "Kafka Consumer")
    Rel(ord_svc, postgres, "12. Persists Order State (Idempotent)", "SQL")
    Rel(ord_svc, kafka, "13. Publishes OrderConfirmed Event", "Kafka Protocol")

    Rel(kafka, ship_svc, "14. Triggers Fulfillment", "Kafka Consumer")
    Rel(ship_svc, courier_sys, "15. Generates Dispatch Label", "HTTPS API")
    Rel(kafka, notif_svc, "16. Consumes All Status Events", "Kafka Consumer")
    Rel(notif_svc, notif_gw, "17. Dispatches Customer Messages", "HTTPS API")
```

---

## Service & Datastore Responsibilities

### 1. Ingress & Edge Layer
* **CDN & Edge WAF:** Intercepts traffic at the edge. Serves cached static assets and immediately blocks non-admitted buyers when stock reaches zero by checking a distributed KV flag (`SOLD_OUT`).
* **API Gateway (Kong):** Validates stateless JWT auth headers, strips illegal request parameters, enforces IP-based rate limiting, and routes legitimate requests downstream.

### 2. Core Microservices
* **Virtual Waiting Room:** Implements a token-bucket queueing system. Limits ingress flow into the Inventory Reservation Service to a safe rate ($100\text{ req/sec}$).
* **Inventory & Reservation Service:** High-performance Go microservice executing atomic stock allocation using Redis Lua scripts. Handles inventory state transitions (`AVAILABLE` $\rightarrow$ `RESERVED`).
* **Payment Service:** Java Spring Boot service wrapping external payment gateways. Implements strict idempotency using `reservation_id`, resilient circuit breakers, and exponential backoff retry algorithms.
* **Order Service:** Maintains the definitive order lifecycle state machine (`CREATED` $\rightarrow$ `PAYMENT_PENDING` $\rightarrow$ `CONFIRMED` $\rightarrow$ `SHIPPED`). Utilizes idempotent consumers (`processed_events` table) to guarantee exactly-once order generation even under broker retries or service restarts.

### 3. Data & Event Streaming Infrastructure
* **Redis Cluster:** Memory-tier gatekeeper. Evaluates stock decrement operations in $<2\text{ ms}$ via Lua scripts to eliminate database row contention.
* **PostgreSQL (Primary + Read Replicas):** Authoritative persistent ledger. Enforces relational integrity, transactional outboxes, and explicit `CHECK(available_quantity >= 0)` constraints.
* **Apache Kafka:** Asynchronous backbone. Decouples fast checkout/reservation pipelines from downstream fulfillment, order creation, and notification services.

---

## Architectural Trade-Offs

1. **Microservice Granularity vs Operational Complexity:**
   * *Trade-off:* Splitting Checkout, Inventory, Payment, and Order into discrete microservices requires network hops, gRPC serialization overhead, and distributed saga orchestrations.
   * *Justification:* Isolated scaling. High CPU usage in Payment processing or slow response times from Courier Logistics will never starve CPU resources of the core Inventory Reservation engine.
2. **Kafka Eventual Consistency for Orders:**
   * *Trade-off:* Buyers experience a transient 1-2 second delay between payment completion and order confirmation UI rendering.
   * *Justification:* Guaranteed durability. If the Order Service experiences a 30-second crash, Kafka holds `PaymentConfirmed` events safely without losing customer payments or aborting transactions.
