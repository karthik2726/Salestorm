# SALESTORM REST API Architectural Design Notes

This document provides detailed design specifications, rate-limiting semantics, error contracts, and idempotency guarantees for the SALESTORM API suite.

---

## 1. Idempotency Key Semantics

All state-modifying POST operations (`/v1/reservations`, `/v1/payments`, `/v1/orders`) **require** an `Idempotency-Key` HTTP header.

### Processing Lifecycle:
1. **Client Header Injection:** The mobile or web client generates a UUIDv4 string (e.g., `idemp-9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d`) prior to dispatching the HTTP request.
2. **Gateway / Service Interception:**
   * The API Gateway checks Redis key `idemp:{endpoint}:{idempotency_key}`.
   * **State 1: Key Not Found:** Execution proceeds normally. Upon completion, the response body and HTTP status code are stored in Redis with a 24-hour TTL (`EX 86400`).
   * **State 2: Key In-Flight:** If an identical request arrives while the original request is still processing, the system returns an immediate `HTTP 409 Conflict` or `HTTP 202 Accepted` with header `Retry-After: 1`.
   * **State 3: Key Complete:** Returns the cached response body and status code directly without re-executing business logic.

---

## 2. Standardized Error Response Contract

All non-2xx HTTP responses adhere to a strict, structured RFC-7807 compatible JSON format:

```json
{
  "error_code": "OUT_OF_STOCK",
  "message": "The requested item 'Product X' has zero available stock.",
  "timestamp": "2026-10-05T09:40:00Z",
  "path": "/v1/reservations",
  "details": [
    {
      "field": "quantity",
      "issue": "Requested 1 unit, available 0"
    }
  ]
}
```

### Core HTTP Status Code Dictionary

| HTTP Code | Error Code | Operational Cause & Client Action |
| :--- | :--- | :--- |
| `201 Created` | N/A | Resource successfully generated (Reservation created). |
| `202 Accepted` | `WAITING_ROOM_QUEUED` | Request placed in virtual queue. Poll `/v1/queue/status`. |
| `409 Conflict` | `OUT_OF_STOCK` | Stock depleted or concurrent reservation conflict. |
| `410 Gone` | `RESERVATION_EXPIRED` | Reservation TTL (>10 minutes) exceeded. Re-attempt purchase. |
| `429 Too Many Requests`| `RATE_LIMIT_EXCEEDED` | Exceeded token bucket quota. Obey `Retry-After` header. |
| `503 Service Unavailable`| `CIRCUIT_OPEN` | External payment gateway or database circuit breaker open. Gracefully retry. |

---

## 3. Rate Limiting Headers

Every response includes standard IETF rate-limiting headers:

```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1728121200
Retry-After: 2
Content-Type: application/json
```

---

## 4. Architectural Trade-Offs

* **Strict Idempotency Storage Overhead:**
  * *Trade-off:* Storing response payloads for all reservations and payments in Redis for 24 hours consumes memory bandwidth.
  * *Justification:* Non-negotiable requirement for financial correctness. Eliminates duplicate credit card charges caused by client-side retries or network drops.
