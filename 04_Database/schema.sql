-- SALESTORM Flash-Sale Relational Schema (PostgreSQL 16)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- 1. CATALOG & USER DOMAIN
-- =============================================================================

CREATE TABLE customer (
    customer_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(30),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE category (
    category_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    slug VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id UUID REFERENCES category(category_id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE product (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id UUID NOT NULL REFERENCES category(category_id),
    sku VARCHAR(64) NOT NULL UNIQUE,
    title VARCHAR(255) NOT NULL,
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- =============================================================================
-- 2. INVENTORY & CONCURRENCY CONTROL LEDGER
-- =============================================================================

CREATE TABLE inventory (
    inventory_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL UNIQUE REFERENCES product(product_id) ON DELETE CASCADE,
    available_quantity INTEGER NOT NULL CHECK (available_quantity >= 0),
    reserved_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
    sold_quantity INTEGER NOT NULL DEFAULT 0 CHECK (sold_quantity >= 0),
    version BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_quantity_sum CHECK (available_quantity >= 0 AND reserved_quantity >= 0 AND sold_quantity >= 0)
);

CREATE INDEX idx_inventory_product_id ON inventory(product_id);

-- =============================================================================
-- 3. FLASH SALE & PROMOTIONS
-- =============================================================================

CREATE TABLE sale (
    sale_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN DEFAULT FALSE NOT NULL,
    CONSTRAINT check_sale_dates CHECK (end_time > start_time)
);

CREATE TABLE deal (
    deal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sale(sale_id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES product(product_id) ON DELETE CASCADE,
    discount_price NUMERIC(12, 2) NOT NULL CHECK (discount_price >= 0),
    allocated_stock INTEGER NOT NULL CHECK (allocated_stock > 0),
    max_per_customer INTEGER NOT NULL DEFAULT 1 CHECK (max_per_customer > 0),
    CONSTRAINT uk_deal_sale_product UNIQUE (sale_id, product_id)
);

CREATE TABLE coupon (
    coupon_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    discount_amount NUMERIC(12, 2) NOT NULL CHECK (discount_amount > 0),
    min_order_value NUMERIC(12, 2) DEFAULT 0 CHECK (min_order_value >= 0),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- =============================================================================
-- 4. CART DOMAIN
-- =============================================================================

CREATE TABLE cart (
    cart_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL UNIQUE REFERENCES customer(customer_id) ON DELETE CASCADE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE cart_item (
    cart_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cart_id UUID NOT NULL REFERENCES cart(cart_id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES product(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    CONSTRAINT uk_cart_product UNIQUE (cart_id, product_id)
);

-- =============================================================================
-- 5. INVENTORY RESERVATION TABLE
-- =============================================================================

CREATE TABLE inventory_reservation (
    reservation_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sale(sale_id),
    customer_id UUID NOT NULL REFERENCES customer(customer_id),
    product_id UUID NOT NULL REFERENCES product(product_id),
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    status VARCHAR(30) NOT NULL CHECK (status IN ('RESERVED', 'PAYMENT_PENDING', 'CONFIRMED', 'RELEASED', 'EXPIRED', 'SOLD')),
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    reserved_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uk_customer_sale_product UNIQUE (sale_id, customer_id, product_id)
);

CREATE INDEX idx_reservation_expires_status ON inventory_reservation(expires_at, status) WHERE status = 'RESERVED';
CREATE INDEX idx_reservation_idempotency ON inventory_reservation(idempotency_key);
CREATE INDEX idx_reservation_customer ON inventory_reservation(customer_id);

-- =============================================================================
-- 6. ORDER ENGINE
-- =============================================================================

CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customer(customer_id),
    reservation_id UUID NOT NULL UNIQUE REFERENCES inventory_reservation(reservation_id),
    order_number VARCHAR(64) NOT NULL UNIQUE,
    status VARCHAR(30) NOT NULL CHECK (status IN ('CREATED', 'PAYMENT_PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'REFUNDED')),
    total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);

CREATE TABLE order_item (
    order_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES product(product_id),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    quantity INTEGER NOT NULL CHECK (quantity > 0)
);

-- =============================================================================
-- 7. PAYMENT & LOGISTICS
-- =============================================================================

CREATE TABLE payment (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL UNIQUE REFERENCES orders(order_id),
    reservation_id UUID NOT NULL REFERENCES inventory_reservation(reservation_id),
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    transaction_ref VARCHAR(128) UNIQUE,
    gateway_provider VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL CHECK (status IN ('INITIATED', 'SUCCESS', 'FAILED', 'UNKNOWN', 'REFUNDED')),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_payment_idempotency ON payment(idempotency_key);
CREATE INDEX idx_payment_status ON payment(status);

CREATE TABLE shipment (
    shipment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL UNIQUE REFERENCES orders(order_id),
    tracking_number VARCHAR(128) UNIQUE,
    carrier VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL CHECK (status IN ('LABEL_CREATED', 'DISPATCHED', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED')),
    dispatched_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE notification (
    notification_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES customer(customer_id),
    channel VARCHAR(20) NOT NULL CHECK (channel IN ('EMAIL', 'SMS', 'PUSH')),
    template_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    sent_at TIMESTAMP WITH TIME ZONE
);

-- =============================================================================
-- 8. TRANSACTIONAL OUTBOX, CONSUMER IDEMPOTENCY & AUDIT LEDGER
-- =============================================================================

CREATE TABLE outbox_event (
    event_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id VARCHAR(128) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    processed BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_outbox_unprocessed ON outbox_event(created_at) WHERE processed = FALSE;

CREATE TABLE processed_event (
    event_id UUID NOT NULL,
    consumer_group VARCHAR(100) NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (event_id, consumer_group)
);

CREATE TABLE audit_log (
    audit_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_name VARCHAR(50) NOT NULL,
    entity_id VARCHAR(128) NOT NULL,
    action VARCHAR(50) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    performed_by VARCHAR(100) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_audit_entity ON audit_log(entity_name, entity_id);
