# Design Patterns Architectural Mapping & Extension Guide

This document details the software design patterns implemented across the SALESTORM codebase, outlining problems solved, class usages, trade-offs, and step-by-step developer extension guides.

---

## 1. Design Pattern Matrix

| Pattern Name | Problem Solved | Codebase Location / Class | Architectural Trade-Off Introduced |
| :--- | :--- | :--- | :--- |
| **Strategy Pattern** | Dynamic selection of pricing discount algorithms and payment gateway routing at runtime. | `PricingStrategy`, `PaymentGatewayAdapter` | Increases class count; requires client to configure strategy selection rules. |
| **Factory Pattern** | Instantiates appropriate gateway adapters (Stripe, Adyen) based on provider configuration. | `PaymentGatewayFactory` | Centralizes creation logic; adding new providers requires updating factory registry. |
| **State Pattern** | Manages legal state transitions and prevents illegal status jumps (`SHIPPED` $\rightarrow$ `CREATED`). | `OrderStateMachineEngine`, `ReservationState` | Complex state configuration tables; adds memory overhead per active state. |
| **Observer Pattern** | Decouples core transaction processing from downstream side-effects (SMS/email notifications). | Kafka Event Listeners (`NotificationService`) | Asynchronous eventual consistency; notifications arrive 1-2s after transaction. |
| **Adapter Pattern** | Normalizes heterogeneous third-party REST APIs (Stripe, FedEx) into unified internal interfaces. | `StripeGatewayAdapter`, `FedExCourierAdapter` | Requires mapping third-party DTOs to internal domain models. |
| **Repository Pattern**| Encapsulates SQL database queries behind clean domain collection interfaces. | `PostgresInventoryRepositoryImpl`, `OrderRepository` | Abstraction layer overhead; can obscure DB performance optimization details. |
| **Facade Pattern** | Simplifies multi-step checkout workflow into a single unified entry point for clients. | `CheckoutFacade` | Risk of Facade class becoming a god object if not strictly scoped. |
| **Circuit Breaker** | Prevents cascading system failure when external payment APIs time out or crash. | `CircuitBreakerManager` (Resilience4j) | Trips open during temporary network blips, temporarily blocking valid traffic. |

---

## 2. Developer Extension Guide: Adding New Integrations

The SALESTORM architecture is designed for zero-touch extension (Open/Closed Principle). The following guides demonstrate how to add new modules with minimal code changes.

```
[New Provider: PayPal] ──> Implement `PaymentGatewayAdapter` ──> Register in `PaymentGatewayFactory`
```

### Guide A: Adding a New Payment Provider (e.g., PayPal)
1. **Create Adapter Class:** Implement `PaymentGatewayAdapter` interface:
   ```java
   public class PayPalGatewayAdapter implements PaymentGatewayAdapter {
       @Override
       public GatewayResponse charge(PaymentChargeRequest req) {
           // PayPal API SDK invocation logic
       }
   }
   ```
2. **Register in Factory:** Inject spring bean into `PaymentGatewayFactory`:
   ```java
   adapters.put("PAYPAL", paypalGatewayAdapter);
   ```
3. **No Existing Code Modified:** Core `PaymentServiceImpl` remains completely untouched.

### Guide B: Adding a New Pricing Strategy (e.g., Flash Tiered Discount)
1. **Implement Strategy Interface:**
   ```java
   public class TieredDiscountStrategy implements PricingStrategy {
       @Override
       public decimal calculatePrice(Product product, int quantity) {
           return product.getPrice().multiply(0.80); // 20% flash discount
       }
   }
   ```
2. **Inject into Checkout Facade:** Register strategy in `CheckoutFacade` calculation pipeline.

### Guide C: Adding a New Delivery Partner (e.g., DHL)
1. **Implement Courier Adapter:**
   ```java
   public class DHLCourierAdapter implements CourierAdapter {
       @Override
       public ShippingLabel createDispatchLabel(Order order) {
           // DHL REST API call
       }
   }
   ```
2. **Subscribe to Kafka Topic:** Register listener on `order-events` to trigger DHL label generation asynchronously.

---

## 3. Comprehensive Architectural Trade-Off Analysis

* **Pattern Abstraction vs Code Simplicity:**
  * *Trade-off:* Utilizing 8 design patterns increases the total number of classes and interfaces across microservices.
  * *Justification:* Necessary for enterprise hackathon code quality, maintainability, unit testability, and isolated failure domain management under 500,000 req/sec scale.
