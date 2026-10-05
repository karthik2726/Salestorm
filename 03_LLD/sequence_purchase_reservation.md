# Sequence Diagram: Purchase & Inventory Reservation

This document illustrates the detailed message sequence for user authentication, admission control, and atomic inventory reservation.

```mermaid
sequenceDiagram
    autonumber
    actor Client as User Mobile App
    participant CDN as CDN Edge / WAF
    participant Gate as API Gateway (Kong)
    participant Queue as Virtual Waiting Room
    participant InvSvc as Inventory Service
    participant Redis as Redis Cluster
    participant DB as PostgreSQL DB

    Client->>CDN: POST /api/v1/reservations (Header: Idempotency-Key, Auth JWT)
    CDN->>Gate: Forward Authorized Ingress Request
    Gate->>Gate: Validate JWT Claims & Rate Limit Token Bucket
    
    alt Ingress Exceeds Throttle Capacity
        Gate-->>Queue: Enqueue Request Ticket
        Queue-->>Client: 202 Accepted (ticket_id, Retry-After: 2s)
        Note over Client, Queue: Client polls queue status until admitted
    end

    Gate->>InvSvc: Reserve Stock (sale_id, product_id, quantity=1)
    
    InvSvc->>Redis: EVALSHA reserve_stock.lua (Keys: stock, idemp, cust)
    
    alt Stock Available (qty >= 1)
        Redis-->>InvSvc: SUCCESS (reservation_id, TTL=600s, Stock=99)
        InvSvc->>DB: BEGIN TX
        InvSvc->>DB: INSERT INTO inventory_reservation (status='RESERVED')
        InvSvc->>DB: INSERT INTO outbox_event (ReservationCreated)
        InvSvc->>DB: COMMIT TX
        InvSvc-->>Gate: 201 Created (reservation_id, expires_at)
        Gate-->>Client: 201 Created (Proceed to Payment)
    else Stock Depleted (qty == 0)
        Redis-->>InvSvc: OUT_OF_STOCK
        InvSvc-->>Gate: 409 Conflict (Out of Stock)
        Gate-->>Client: 409 Conflict (Sold Out)
        Note over Redis, CDN: Redis emits event -> CDN KV 'SOLD_OUT' flag set to TRUE
    end
```

---

## Key Execution Phases

1. **Edge Interception & Token Bucket Rate Limiting:** API Gateway strips invalid JWTs and enforces user IP rate limits.
2. **Atomic Lua Gate:** Redis evaluates stock decrement in single-threaded memory thread ($<1.5\text{ ms}$).
3. **Outbox Pattern:** Local ACID SQL transaction writes reservation record and outbox event simultaneously.

---

## Architectural Trade-Offs

* **Waiting Room Polling Overhead:**
  * *Trade-off:* 202 Accepted polling forces clients to send repeated status HTTP requests every 2 seconds.
  * *Justification:* Shields backend microservices from unpredictable traffic spikes.
