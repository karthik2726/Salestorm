# Low-Level Class Diagram: Payment Service

This document details the internal class structure for the Payment microservice, highlighting payment gateway abstraction, circuit breaker fault-tolerance, and idempotency enforcement.

```mermaid
classDiagram
    class PaymentController {
        -PaymentService paymentService
        -PaymentIdempotencyGuard idempotencyGuard
        +processPayment(PaymentRequest req, String idempotencyKey) PaymentResponse
        +handleWebhook(String provider, String payload, String signature) WebhookResponse
    }

    class PaymentIdempotencyGuard {
        -RedisTemplate redisTemplate
        -PaymentRepository paymentRepo
        +checkAndLock(String idempotencyKey) IdempotencyState
        +cacheResponse(String idempotencyKey, PaymentResponse response) void
    }

    class PaymentService {
        <<interface>>
        +executePayment(PaymentCommand cmd) PaymentResult
        +reconcileUnknownPayment(String paymentId) PaymentResult
    }

    class PaymentServiceImpl {
        -PaymentGatewayFactory gatewayFactory
        -CircuitBreakerManager circuitBreaker
        -PaymentRepository paymentRepo
        -OutboxPublisher outboxPublisher
        +executePayment(PaymentCommand cmd) PaymentResult
        +reconcileUnknownPayment(String paymentId) PaymentResult
    }

    class PaymentGatewayFactory {
        -Map~String, PaymentGatewayAdapter~ adapters
        +getAdapter(String providerName) PaymentGatewayAdapter
    }

    class PaymentGatewayAdapter {
        <<interface>>
        +charge(PaymentChargeRequest req) GatewayResponse
        +verifyStatus(String transactionRef) GatewayResponse
        +refund(String transactionRef, decimal amount) GatewayResponse
    }

    class StripeGatewayAdapter {
        -StripeClient stripeClient
        +charge(PaymentChargeRequest req) GatewayResponse
        +verifyStatus(String transactionRef) GatewayResponse
        +refund(String transactionRef, decimal amount) GatewayResponse
    }

    class AdyenGatewayAdapter {
        -AdyenClient adyenClient
        +charge(PaymentChargeRequest req) GatewayResponse
        +verifyStatus(String transactionRef) GatewayResponse
        +refund(String transactionRef, decimal amount) GatewayResponse
    }

    class CircuitBreakerManager {
        -CircuitBreaker circuitBreaker
        +executeSupplier(Supplier~T~ supplier) T
    }

    class PaymentReconciliationScheduler {
        -PaymentRepository paymentRepo
        -PaymentGatewayFactory gatewayFactory
        +reconcilePendingPayments() void
    }

    class Payment {
        -String paymentId
        -String orderId
        -String reservationId
        -String idempotencyKey
        -String transactionRef
        -PaymentStatus status
        -decimal amount
        +markSuccess(String ref) void
        +markFailed(String reason) void
        +markUnknown() void
    }

    PaymentController --> PaymentIdempotencyGuard
    PaymentController --> PaymentService
    PaymentService <|.. PaymentServiceImpl
    PaymentServiceImpl --> PaymentGatewayFactory
    PaymentServiceImpl --> CircuitBreakerManager
    PaymentServiceImpl --> PaymentRepository
    PaymentGatewayFactory --> PaymentGatewayAdapter
    PaymentGatewayAdapter <|.. StripeGatewayAdapter
    PaymentGatewayAdapter <|.. AdyenGatewayAdapter
    PaymentReconciliationScheduler --> PaymentRepository
    PaymentReconciliationScheduler --> PaymentGatewayFactory
    PaymentServiceImpl ..> Payment
```

---

## Component Responsibilities & Exception Handling

1. **`PaymentIdempotencyGuard` (Idempotency Filter):**
   * Checks Redis for active `idempotency_key`.
   * Throws `DuplicatePaymentException` or returns cached `PaymentResponse` if already processed.
2. **`CircuitBreakerManager` (Fault Isolation):**
   * Wraps external network calls to Stripe/Adyen.
   * Intercepts `TimeoutException` or `ConnectException`. If error rate > 50%, trips circuit to `OPEN`, throwing `CallNotPermittedException` (HTTP 503 Service Unavailable).
3. **`PaymentGatewayFactory` & Adapters (Strategy Pattern):**
   * Decouples payment execution logic from provider-specific REST APIs. Allows seamless fallback from Stripe to Adyen.
4. **`PaymentReconciliationScheduler` (Indeterminate State Resolution):**
   * Polling engine inspecting payments stuck in `PAYMENT_UNKNOWN` state. Queries external gateway APIs to resolve status safely without duplicate charges.

---

## Architectural Trade-Offs

* **Circuit Breaker Retry Delays:**
  * *Trade-off:* When the circuit breaker trips `OPEN`, valid customer payments are immediately rejected with HTTP 503 for a 10-second sleep window.
  * *Justification:* Prevents thread pool exhaustion and keeps the payment microservice responsive for other system operations during external provider degradation.
