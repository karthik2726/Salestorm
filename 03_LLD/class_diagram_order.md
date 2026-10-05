# Low-Level Class Diagram: Order Service

This document describes the Object-Oriented structure of the Order microservice, detailing state machine management, consumer idempotency, and compensation saga orchestration.

```mermaid
classDiagram
    class OrderKafkaConsumer {
        -IdempotentEventProcessor eventProcessor
        -OrderService orderService
        +onPaymentConfirmed(ConsumerRecord record) void
        +onPaymentFailed(ConsumerRecord record) void
    }

    class IdempotentEventProcessor {
        -ProcessedEventRepository processedEventRepo
        +isAlreadyProcessed(String eventId, String consumerGroup) boolean
        +markProcessed(String eventId, String consumerGroup) void
    }

    class OrderService {
        <<interface>>
        +createOrderFromPayment(String reservationId, String paymentId, decimal amount) OrderResult
        +updateOrderStatus(String orderId, OrderEvent event) boolean
        +cancelOrderWithCompensation(String orderId, String reason) void
    }

    class OrderServiceImpl {
        -OrderRepository orderRepo
        -OrderStateMachineEngine stateMachineEngine
        -SagaCompensationHandler sagaHandler
        -OutboxPublisher outboxPublisher
        +createOrderFromPayment(String reservationId, String paymentId, decimal amount) OrderResult
        +updateOrderStatus(String orderId, OrderEvent event) boolean
        +cancelOrderWithCompensation(String orderId, String reason) void
    }

    class OrderStateMachineEngine {
        -StateMachine~OrderStatus, OrderEvent~ stateMachine
        +fireEvent(Order order, OrderEvent event) OrderStatus
        +validateTransition(OrderStatus current, OrderStatus target) boolean
    }

    class SagaCompensationHandler {
        -OutboxPublisher outboxPublisher
        -PaymentServiceAdapter paymentAdapter
        +triggerRefundAndStockRelease(String orderId, String reservationId) void
    }

    class OrderRepository {
        <<interface>>
        +findById(String orderId) Order
        +findByReservationId(String reservationId) Order
        +save(Order order) Order
        +updateStatus(String orderId, OrderStatus status) void
    }

    class Order {
        -String orderId
        -String customerId
        -String reservationId
        -String orderNumber
        -OrderStatus status
        -decimal totalAmount
        -List~OrderItem~ items
        +transitionTo(OrderStatus nextStatus) void
        +canBeCancelled() boolean
    }

    OrderKafkaConsumer --> IdempotentEventProcessor
    OrderKafkaConsumer --> OrderService
    OrderService <|.. OrderServiceImpl
    OrderServiceImpl --> OrderRepository
    OrderServiceImpl --> OrderStateMachineEngine
    OrderServiceImpl --> SagaCompensationHandler
    OrderServiceImpl ..> Order
```

---

## Component Responsibilities & State Handling

1. **`IdempotentEventProcessor` (Consumer Guard):**
   * Inspects `processed_event` database table before executing business logic. Catches `DuplicateEventException` and commits Kafka offsets safely without processing duplicates.
2. **`OrderStateMachineEngine` (State Control):**
   * Enforces legal order state transitions (`CREATED` $\rightarrow$ `CONFIRMED` $\rightarrow$ `PROCESSING` $\rightarrow$ `SHIPPED` $\rightarrow$ `DELIVERED`). Throws `IllegalStateTransitionException` if invalid transitions are attempted (e.g., `SHIPPED` $\rightarrow$ `CREATED`).
3. **`SagaCompensationHandler` (Rollback Engine):**
   * Executes saga compensation workflows if downstream order fulfillment fails. Publishes `RefundInitiated` and `StockReleaseRequested` events to Kafka.

---

## Architectural Trade-Offs

* **Strict State Machine Validation:**
  * *Trade-off:* State machine transition rules reject out-of-order Kafka events (e.g., `ShipmentDispatched` arriving before `OrderConfirmed`).
  * *Justification:* Prevents corrupting order lifecycle data. Out-of-order events are routed to a Kafka retry buffer topic to await parent state completion.
