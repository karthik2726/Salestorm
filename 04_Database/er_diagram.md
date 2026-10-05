# Entity-Relationship Diagram (ERD)

This document specifies the relational data model for the SALESTORM platform, illustrating core domain entities, transaction ledgers, event outboxes, and audit logs.

```mermaid
erDiagram
    CATEGORY ||--o{ PRODUCT : "contains"
    PRODUCT ||--|| INVENTORY : "has stock ledger"
    PRODUCT ||--o{ SALE : "featured in"
    SALE ||--o{ DEAL : "offers"
    COUPON }o--o{ SALE : "applies to"

    CUSTOMER ||--o{ CART : "owns"
    CART ||--o{ CART_ITEM : "contains"
    PRODUCT ||--o{ CART_ITEM : "referenced in"

    CUSTOMER ||--o{ INVENTORY_RESERVATION : "places"
    PRODUCT ||--o{ INVENTORY_RESERVATION : "reserves"
    SALE ||--o{ INVENTORY_RESERVATION : "valid for"

    CUSTOMER ||--o{ ORDERS : "places"
    INVENTORY_RESERVATION ||--o| ORDERS : "fulfills"
    ORDERS ||--o{ ORDER_ITEM : "contains"
    PRODUCT ||--o{ ORDER_ITEM : "ordered"

    ORDERS ||--o| PAYMENT : "settled by"
    ORDERS ||--o| SHIPMENT : "dispatched via"
    CUSTOMER ||--o{ NOTIFICATION : "receives"

    CUSTOMER {
        uuid customer_id PK
        string email UK
        string password_hash
        string first_name
        string last_name
        string phone_number
        timestamp created_at
        timestamp updated_at
    }

    CATEGORY {
        uuid category_id PK
        string name UK
        string slug UK
        uuid parent_category_id FK
    }

    PRODUCT {
        uuid product_id PK
        uuid category_id FK
        string sku UK
        string title
        decimal price
        boolean is_active
        timestamp created_at
        timestamp updated_at
    }

    INVENTORY {
        uuid inventory_id PK
        uuid product_id FK,UK
        integer available_quantity
        integer reserved_quantity
        integer sold_quantity
        bigint version
        timestamp updated_at
    }

    SALE {
        uuid sale_id PK
        string title
        timestamp start_time
        timestamp end_time
        boolean is_active
    }

    DEAL {
        uuid deal_id PK
        uuid sale_id FK
        uuid product_id FK
        decimal discount_price
        integer allocated_stock
        integer max_per_customer
    }

    COUPON {
        uuid coupon_id PK
        string code UK
        decimal discount_amount
        decimal min_order_value
        timestamp expires_at
    }

    CART {
        uuid cart_id PK
        uuid customer_id FK,UK
        timestamp updated_at
    }

    CART_ITEM {
        uuid cart_item_id PK
        uuid cart_id FK
        uuid product_id FK
        integer quantity
    }

    INVENTORY_RESERVATION {
        uuid reservation_id PK
        uuid sale_id FK
        uuid customer_id FK
        uuid product_id FK
        string idempotency_key UK
        string status
        integer quantity
        timestamp reserved_at
        timestamp expires_at
    }

    ORDERS {
        uuid order_id PK
        uuid customer_id FK
        uuid reservation_id FK,UK
        string order_number UK
        string status
        decimal total_amount
        timestamp created_at
        timestamp updated_at
    }

    ORDER_ITEM {
        uuid order_item_id PK
        uuid order_id FK
        uuid product_id FK
        decimal unit_price
        integer quantity
    }

    PAYMENT {
        uuid payment_id PK
        uuid order_id FK,UK
        uuid reservation_id FK
        string idempotency_key UK
        string transaction_ref UK
        string gateway_provider
        string status
        decimal amount
        timestamp created_at
    }

    SHIPMENT {
        uuid shipment_id PK
        uuid order_id FK,UK
        string tracking_number UK
        string carrier
        string status
        timestamp dispatched_at
        timestamp delivered_at
    }

    NOTIFICATION {
        uuid notification_id PK
        uuid customer_id FK
        string channel
        string template_id
        string status
        timestamp sent_at
    }

    OUTBOX_EVENT {
        uuid event_id PK
        string aggregate_type
        string aggregate_id
        string event_type
        jsonb payload
        boolean processed
        timestamp created_at
    }

    PROCESSED_EVENT {
        uuid event_id PK
        string consumer_group
        timestamp processed_at
    }

    AUDIT_LOG {
        uuid audit_id PK
        string entity_name
        string entity_id
        string action
        jsonb old_values
        jsonb new_values
        string performed_by
        timestamp timestamp
    }
```

---

## Entity Relationship Descriptions

1. **Product & Inventory Ledger:**
   * `PRODUCT` to `INVENTORY` is a 1-to-1 strict relationship. The `INVENTORY` table maintains real-time physical balances (`available_quantity`, `reserved_quantity`, `sold_quantity`).
2. **Flash Sale & Deals:**
   * `SALE` contains multiple `DEAL` entries, defining allocated stock caps and per-customer limits during high-concurrency windows.
3. **Inventory Reservation & Orders:**
   * `INVENTORY_RESERVATION` tracks temporal holds ($10\text{ min}$ TTL). An `ORDERS` record maintains a 1-to-1 reference to a single reservation.
4. **Outbox & Idempotency Infrastructure:**
   * `OUTBOX_EVENT`, `PROCESSED_EVENT`, and `AUDIT_LOG` exist as decoupled transactional infrastructure entities to support reliable event delivery and auditing without foreign key constraints to domain models.

---

## Trade-Off Analysis

* **Decoupled Outbox and Audit Tables:**
  * *Trade-off:* `OUTBOX_EVENT` and `PROCESSED_EVENT` lack foreign keys to `ORDERS` or `INVENTORY_RESERVATION`.
  * *Justification:* Prevents schema lock contention during high-speed batch event writes and allows outbox rows to be purged independently without cascading locks.
