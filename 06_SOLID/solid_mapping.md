# SOLID Principles Architectural Mapping

This document maps the five SOLID object-oriented design principles to explicit microservice classes in SALESTORM, explaining justifications and trade-offs.

---

## 1. SOLID Principle Class Mapping

| Principle | Target Class Name | Single-Line Justification & Architectural Mapping |
| :--- | :--- | :--- |
| **SRP** (Single Responsibility) | `PaymentIdempotencyGuard` | Responsible exclusively for checking and recording payment request idempotency keys in Redis/DB; does not execute charges or manage gateway adapters. |
| **SRP** (Single Responsibility) | `RedisLuaEngine` | Responsible solely for loading and executing atomic Lua scripts against Redis; contains zero database or HTTP controller logic. |
| **OCP** (Open/Closed) | `PaymentGatewayFactory` | Open for extension (new payment gateways like PayPal can be added by implementing `PaymentGatewayAdapter`), closed for modification (existing payment execution logic remains untouched). |
| **OCP** (Open/Closed) | `OrderStateMachineEngine` | Allows adding new order state transition rules via configuration without modifying core order processing pipelines. |
| **LSP** (Liskov Substitution) | `StripeGatewayAdapter` & `AdyenGatewayAdapter` | Both classes substitute `PaymentGatewayAdapter` seamlessly; clients calling `.charge()` receive consistent `GatewayResponse` contracts without type-checking. |
| **ISP** (Interface Segregation) | `InventoryRepository` | Segregates inventory query methods (`findById`) from stock mutation methods (`decrementAvailableQuantity`), ensuring callers depend only on required methods. |
| **DIP** (Dependency Inversion) | `PaymentServiceImpl` | Depends on high-level `PaymentGatewayAdapter` and `PaymentRepository` abstractions rather than concrete API client implementations or SQL drivers. |

---

## 2. Comprehensive Architectural Trade-Off Analysis

1. **Open/Closed Principle (OCP) Trade-Offs:**
   * *Sacrifice:* Introduces additional interface layers, abstract factories, and strategy classes (`PaymentGatewayFactory`, `PaymentGatewayAdapter`).
   * *Justification:* Essential for long-term maintainability. Adding a new payment processor or delivery partner requires zero modifications to existing, tested payment processing code.
2. **Dependency Inversion Principle (DIP) Trade-Offs:**
   * *Sacrifice:* Requires dependency injection framework configurations (Spring `@Autowired` or Go constructor wiring) and interface definitions.
   * *Justification:* Enables effortless unit testing with mock repositories (`MockInventoryRepository`) and isolates business logic from underlying datastore changes.
