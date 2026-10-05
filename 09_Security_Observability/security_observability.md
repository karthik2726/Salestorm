# Comprehensive Security & Observability Blueprint

This document details the unified security controls, PCI compliance measures, structured telemetry logging, distributed tracing propagation, and alerting rules for SALESTORM.

---

## 1. Security Architecture & Threat Defense

### 1.1 Authentication, Authorization & Service Mesh Security
* **User Authentication (JWT):** Stateless Ed25519-signed JWT tokens validated at the API Gateway edge. Claims include `user_id`, `roles` (`ROLE_CUSTOMER`, `ROLE_ADMIN`), and `exp` (15-minute TTL).
* **Service-to-Service Security (mTLS):** All inter-service gRPC and HTTP communication inside the Kubernetes cluster is encrypted via **Istio Service Mesh** using mutual TLS (mTLS) with SPIFFE identities.
* **HTTPS Everywhere:** TLS 1.3 enforced on all external endpoints with HSTS preloading (`max-age=31536000`).

### 1.2 Rate Limiting, Bot Defense & Input Validation
* **Bot Defense:** Cloudflare Edge WAF evaluates TLS fingerprints, IP reputation, and JavaScript challenge tokens to drop automated purchasing scripts.
* **Input Validation:** OpenAPI 3 schema enforcement at Gateway. All REST/gRPC payloads are validated against strict JSON schemas before reaching microservice controllers.

### 1.3 Payment Data Security (PCI-DSS Scope Reduction)
* **Zero Card Storage:** Card numbers and CVVs never touch SALESTORM infrastructure. Stripe/Adyen SDK elements collect card inputs directly on client devices, returning tokenized strings (`tok_1N8XXXXX`).
* **Secrets Management:** Private API keys, DB credentials, and JWT keys are stored in **AWS Secrets Manager** with automatic 30-day rotation and IAM policy restrictions.

---

## 2. Key Metrics & Alert Threshold Matrix

| Metric Name | Category | Normal Baseline | Alert Warning Threshold | Critical Threshold |
| :--- | :--- | :--- | :--- | :--- |
| `salestorm_ingress_requests_total` | Traffic | 10,000 req/s | > 50,000 req/s | > 200,000 req/s |
| `salestorm_reservation_latency_ms` | Latency | p95 < 20 ms | p95 > 50 ms | p95 > 100 ms |
| `salestorm_payment_failure_rate` | Errors | < 5% | > 10% | > 25% |
| `salestorm_inventory_mismatch_count` | Consistency | 0 | > 0 | > 5 |
| `salestorm_kafka_dlq_messages_total`| Errors | 0 | > 0 | > 10 |

---

## 3. Structured JSON Logging Examples

### Example 1: `reservation_created`
```json
{
  "timestamp": "2026-10-05T09:57:00.100Z",
  "level": "INFO",
  "service": "inventory-service",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "event_type": "RESERVATION_CREATED",
  "reservation_id": "res_9981a_uuid",
  "product_id": "prod_flash_x",
  "customer_id": "cust_101",
  "idempotency_key": "idemp_seq_101",
  "stock_remaining": 99
}
```

### Example 2: `reservation_expired`
```json
{
  "timestamp": "2026-10-05T10:07:00.000Z",
  "level": "INFO",
  "service": "inventory-service",
  "trace_id": "8cf92f3577b34da6a3ce929d0e0e4799",
  "event_type": "RESERVATION_EXPIRED",
  "reservation_id": "res_9981a_uuid",
  "reason": "TTL_EXCEEDED_10M",
  "stock_replenished": 1
}
```

### Example 3: `payment_succeeded`
```json
{
  "timestamp": "2026-10-05T09:57:02.340Z",
  "level": "INFO",
  "service": "payment-service",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "event_type": "PAYMENT_SUCCEEDED",
  "payment_id": "pay_8812_uuid",
  "reservation_id": "res_9981a_uuid",
  "transaction_ref": "tx_stripe_9981",
  "amount": 299.99
}
```

### Example 4: `payment_unknown`
```json
{
  "timestamp": "2026-10-05T09:57:05.110Z",
  "level": "WARN",
  "service": "payment-service",
  "trace_id": "7af92f3577b34da6a3ce929d0e0e4111",
  "event_type": "PAYMENT_UNKNOWN",
  "reservation_id": "res_7712_uuid",
  "idempotency_key": "pay_seq_7712",
  "issue": "GATEWAY_TIMEOUT_2000MS"
}
```

### Example 5: `order_created`
```json
{
  "timestamp": "2026-10-05T09:57:03.010Z",
  "level": "INFO",
  "service": "order-service",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "event_type": "ORDER_CREATED",
  "order_id": "ord_5541_uuid",
  "order_number": "ORD-20261005-9981",
  "status": "CONFIRMED"
}
```

### Example 6: `order_creation_failed`
```json
{
  "timestamp": "2026-10-05T09:57:04.500Z",
  "level": "ERROR",
  "service": "order-service",
  "trace_id": "3bf92f3577b34da6a3ce929d0e0e4555",
  "event_type": "ORDER_CREATION_FAILED",
  "reservation_id": "res_1122_uuid",
  "error_code": "CONSTRAINT_VIOLATION",
  "action": "TRIGGER_COMPENSATION_SAGA"
}
```

---

## 4. Distributed Tracing Header Propagation

Tracing uses OpenTelemetry W3C Distributed Tracing standard:

* **HTTP Header:** `traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
* **Kafka Record Headers:**
  * `trace_id`: `4bf92f3577b34da6a3ce929d0e0e4736`
  * `correlation_id`: `corr_req_9981a`

This guarantees that a single purchase request can be traced seamlessly across Checkout $\rightarrow$ Inventory $\rightarrow$ Payment $\rightarrow$ Kafka $\rightarrow$ Order Service $\rightarrow$ Notification.

---

## 5. Prometheus Alert Rules

```yaml
groups:
  - name: salestorm_alerts
    rules:
      - alert: InventoryInconsistencyAlert
        expr: abs(salestorm_redis_stock - (salestorm_db_stock - salestorm_active_reservations)) > 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Redis and DB stock ledgers have diverged."

      - alert: PaymentFailureSpike
        expr: rate(salestorm_payment_failed_total[1m]) / rate(salestorm_payment_attempted_total[1m]) > 0.25
        for: 1m
        labels:
          severity: high
        annotations:
          summary: "Payment failure rate exceeded 25%."

      - alert: DLQNonEmptyAlert
        expr: salestorm_kafka_dlq_messages_total > 0
        for: 0s
        labels:
          severity: critical
        annotations:
          summary: "Dead Letter Queue has unhandled messages."
```

---

## 6. Architectural Trade-Offs

* **Telemetry Storage Overhead:**
  * *Trade-off:* Storing structured JSON logs and distributed traces under 500,000 req/sec load generates massive log volume.
  * *Justification:* Mitigated by setting probabilistic trace sampling to $1\%$ for standard requests and $100\%$ for errors and high-latency spans.
