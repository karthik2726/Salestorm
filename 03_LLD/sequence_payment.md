# Sequence Diagram: Payment Settlement & Reconciliation

This document details the payment processing sequence across success, decline, timeout (`PAYMENT_UNKNOWN`), background reconciliation, and duplicate request idempotency flows.

```mermaid
sequenceDiagram
    autonumber
    actor Client as Customer Mobile App
    participant PaySvc as Payment Service
    participant Guard as Idempotency Guard (Redis)
    participant CB as Circuit Breaker (Resilience4j)
    participant Stripe as Stripe Gateway API
    participant DB as PostgreSQL DB
    participant Kafka as Apache Kafka

    Note over Client, PaySvc: Case 1: Standard Successful Payment Flow
    Client->>PaySvc: POST /v1/payments (Idempotency-Key: K1, reservation_id: R1)
    PaySvc->>Guard: Check & Lock Key (K1)
    Guard-->>PaySvc: Key Lock Acquired (First execution)
    
    PaySvc->>CB: Execute Charge Request
    CB->>Stripe: POST /v1/charges (Amount, CardToken)
    Stripe-->>CB: 200 OK (transaction_ref: tx_9988)
    CB-->>PaySvc: Charge Successful
    
    PaySvc->>DB: BEGIN TX
    PaySvc->>DB: INSERT INTO payment (status='SUCCESS', transaction_ref='tx_9988')
    PaySvc->>DB: INSERT INTO outbox_event (PaymentConfirmed)
    PaySvc->>DB: COMMIT TX
    PaySvc->>Kafka: Publish PaymentConfirmed event
    PaySvc-->>Client: 200 OK (Payment Confirmed)

    Note over Client, PaySvc: Case 2: Duplicate Payment Request (Idempotency Protection)
    Client->>PaySvc: POST /v1/payments (Idempotency-Key: K1) [DUPLICATE]
    PaySvc->>Guard: Check Key (K1)
    Guard-->>PaySvc: Key Found (Status: SUCCESS, Payload: Cached Response)
    PaySvc-->>Client: 200 OK (Return Cached Response - Zero Re-charge)

    Note over Client, PaySvc: Case 3: Gateway Timeout -> PAYMENT_UNKNOWN -> Reconciliation
    Client->>PaySvc: POST /v1/payments (Idempotency-Key: K2)
    PaySvc->>CB: Execute Charge Request
    CB->>Stripe: POST /v1/charges
    Note over Stripe: Network Timeout (>2000ms delay)
    Stripe--/CB: Network Drop / Timeout Exception
    
    PaySvc->>DB: INSERT INTO payment (status='UNKNOWN', idempotency_key='K2')
    PaySvc-->>Client: 202 Accepted ("Payment Pending Verification")
    
    loop Every 30 seconds (Background Reconciliation)
        participant Recon as Payment Reconciliation Cron
        Recon->>DB: SELECT * FROM payment WHERE status = 'UNKNOWN'
        Recon->>Stripe: GET /v1/charges?idempotency_key=K2
        alt Stripe Confirms Charge Succeeded
            Stripe-->>Recon: Charge Found (status = 'succeeded', ref: tx_7711)
            Recon->>DB: UPDATE payment SET status='SUCCESS', transaction_ref='tx_7711'
            Recon->>Kafka: Publish PaymentConfirmed event
        else Stripe Confirms Charge Failed
            Stripe-->>Recon: Charge Not Found / Failed
            Recon->>DB: UPDATE payment SET status='FAILED'
            Recon->>Kafka: Publish PaymentFailed event (Triggers Inventory Release)
        end
    end
```

---

## Detailed Scenario Analysis

1. **Successful Execution:** Synchronous gateway settlement completes in $<800\text{ ms}$. Transactional outbox guarantees `PaymentConfirmed` event dispatch.
2. **Duplicate Request Handling:** `PaymentIdempotencyGuard` intercepts duplicate `Idempotency-Key` headers in Redis memory ($<2\text{ ms}$), returning the stored HTTP response payload without calling Stripe.
3. **Indeterminate State (`PAYMENT_UNKNOWN`):** Network timeouts transition payment state to `UNKNOWN` rather than guessing failure. Background polling queries Stripe using the same `Idempotency-Key` to resolve final state safely.

---

## Architectural Trade-Offs

* **Indeterminate Polling Latency:**
  * *Trade-off:* When network drops occur, buyers wait 15-30 seconds for background reconciliation to finalize order status.
  * *Justification:* Prevents double-charging cards or releasing valid reservations prematurely.
