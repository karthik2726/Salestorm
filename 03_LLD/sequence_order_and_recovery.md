# Sequence Diagram: Resilient Order Creation & Outage Recovery

This document details event-driven order creation, consumer idempotency during a 30-second Order Service container outage, and compensation saga refund workflows.

```mermaid
sequenceDiagram
    autonumber
    participant PaySvc as Payment Service
    participant Kafka as Apache Kafka (`payment-events` topic)
    participant OrdSvc as Order Service (Recovered)
    participant DB as PostgreSQL DB
    participant Notif as Notification Service
    participant Stripe as Stripe Gateway API

    PaySvc->>Kafka: Publish PaymentConfirmed event (reservation_id: R1, payment_id: P1)
    
    Note over OrdSvc: t = 0s to 30s: Order Service is DOWN (Container Crash / Outage)
    Note over Kafka: Kafka retains PaymentConfirmed event durably in partition log

    Note over OrdSvc: t = 30s: Order Service Pod Recovers & Reconnects
    Kafka->>OrdSvc: Poll Batch Events (Delivers PaymentConfirmed event)
    
    OrdSvc->>DB: BEGIN TX
    OrdSvc->>DB: INSERT INTO processed_event (event_id, consumer_group='order-service')
    
    alt Event Not Yet Processed (First Execution)
        DB-->>OrdSvc: Insert SUCCESS (1 row)
        OrdSvc->>DB: INSERT INTO orders (reservation_id: R1, status='CONFIRMED')
        OrdSvc->>DB: UPDATE inventory_reservation SET status='CONFIRMED'
        OrdSvc->>DB: INSERT INTO outbox_event (OrderConfirmed)
        OrdSvc->>DB: COMMIT TX
        
        OrdSvc->>Kafka: Commit Kafka Message Offset
        OrdSvc->>Kafka: Publish OrderConfirmed event
        Kafka->>Notif: Consume OrderConfirmed -> Send Email Receipt
    else Event Already Processed (Duplicate Consumer Rebalance)
        DB-->>OrdSvc: Unique Constraint Violation (ON CONFLICT DO NOTHING)
        OrdSvc->>DB: ROLLBACK TX
        OrdSvc->>Kafka: Commit Kafka Message Offset (Skip processing)
    end

    Note over OrdSvc, Stripe: Compensation Saga Path (Fatal Business Failure / Validation Drop)
    alt Fatal Order Creation Constraint Failure
        OrdSvc->>DB: INSERT INTO orders (status='CANCELLED')
        OrdSvc->>Kafka: Publish OrderCreationFailed event
        Kafka->>PaySvc: Consume OrderCreationFailed -> Initiate Refund
        PaySvc->>Stripe: POST /v1/refunds (transaction_ref)
        PaySvc->>Kafka: Publish InventoryReleaseRequested event
    end
```

---

## Key Resilience Mechanisms

1. **Kafka Buffer Durability:** During the 30-second Order Service downtime, Kafka retains unconsumed `PaymentConfirmed` events safely without losing messages or failing upstream payments.
2. **Consumer Idempotency:** The `processed_event` database table guarantees that consumer restarts or partition rebalances never produce duplicate order rows.
3. **Automated Compensation Saga:** If order creation encounters unrecoverable errors, a compensation event triggers a full financial refund via Stripe and stock restoration in Redis.

---

## Architectural Trade-Offs

* **Transactional Outbox Scraper Delay:**
  * *Trade-off:* Outbox polling thread introduces a ~50ms delay between DB transaction commit and Kafka message availability.
  * *Justification:* Guarantees dual-write consistency. DB changes and Kafka events never become out-of-sync.
