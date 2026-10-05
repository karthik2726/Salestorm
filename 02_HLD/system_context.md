# C4 Level 1: System Context Diagram

The System Context diagram outlines the boundaries of the SALESTORM platform, its primary human users, and external integrations.

```mermaid
C4Context
    title System Context Diagram for SALESTORM Flash-Sale Platform

    Person(customer, "Flash Sale Customer", "Browses flash sale products, queues, reserves stock, and completes checkout.")
    Person(admin, "Sale Operations Admin", "Configures flash sales, sets stock allocations, monitors real-time metrics, and handles manual reconciliations.")

    System(salestorm, "SALESTORM Platform", "High-concurrency flash sale e-commerce platform ensuring zero overselling, zero double-charging, and strict order lifecycle integrity.")

    System_Ext(payment_gw, "External Payment Gateway", "Stripe / Adyen API for credit card processing, authorization, and 3D-Secure authentication.")
    System_Ext(courier_sys, "Logistics Courier System", "FedEx / DHL API for automated shipping label generation and real-time package delivery tracking.")
    System_Ext(notification_provider, "Notification Gateways", "Twilio (SMS) & SendGrid (Email) services for transactional message dispatch.")

    Rel(customer, salestorm, "Browses sales, joins waiting queue, reserves inventory, completes payment", "HTTPS / REST / WebSockets")
    Rel(admin, salestorm, "Configures sales stock, views monitoring dashboards, triggers reconciliation", "HTTPS / Admin UI")

    Rel(salestorm, payment_gw, "Processes credit card transactions, verifies payments, issues refunds", "HTTPS / REST API")
    Rel(salestorm, courier_sys, "Dispatches manifest data, retrieves tracking status updates", "HTTPS / Webhooks / REST API")
    Rel(salestorm, notification_provider, "Dispatches transactional emails and SMS notifications", "HTTPS / REST API")
```

---

## Component Rationale & Architecture Justification

### 1. SALESTORM Platform Core
* **Why it exists:** Provides an isolated, resilient system designed specifically to survive 500,000 req/s flash sale ingress traffic spikes while preserving strict transactional guarantees for inventory, payments, and orders.
* **Key Responsibility:** Manages state transitions from browsing to order delivery, preventing resource starvation of core database engines.

### 2. External Payment Gateway (Stripe/Adyen)
* **Why it exists:** Offloads PCI-DSS compliance and financial settlement infrastructure.
* **Integration Pattern:** Synchronous tokenized charge requests with async fallback webhooks for handling network drops and pending state resolutions.

### 3. External Logistics Courier System (FedEx/DHL)
* **Why it exists:** Handles physical packaging label creation and route tracking.
* **Integration Pattern:** Fully asynchronous background event invocation driven by post-checkout fulfillment services.

### 4. External Notification Providers (Twilio/SendGrid)
* **Why it exists:** Isolates bulk outbound message delivery (email/SMS) from core transaction processing threads.

---

## Trade-Off Analysis

* **External Dependency Coupling:**
  * *Trade-off:* Relying on external payment gateways introduces non-deterministic latency (500ms to 2000ms) and potential external API outages.
  * *Mitigation:* SALESTORM isolates payment gateway calls behind circuit breakers, bounded timeout retries, and asynchronous transactional state handling (`PAYMENT_UNKNOWN`).
