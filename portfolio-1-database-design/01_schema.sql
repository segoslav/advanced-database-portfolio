-- =====================================================================
-- ShopNaija Online Marketplace — Relational Schema
-- MIT 8103 Advanced Database Systems — Portfolio 1
-- Target: PostgreSQL 15+
--
-- Run this file FIRST, while connected to the "shopnaija" database.
-- It is safe to re-run: it drops and recreates every table.
-- =====================================================================

-- Start clean (drop in reverse dependency order)
DROP TABLE IF EXISTS delivery_events  CASCADE;
DROP TABLE IF EXISTS shipments        CASCADE;
DROP TABLE IF EXISTS delivery_agents  CASCADE;
DROP TABLE IF EXISTS payments         CASCADE;
DROP TABLE IF EXISTS order_items      CASCADE;
DROP TABLE IF EXISTS orders           CASCADE;
DROP TABLE IF EXISTS inventory        CASCADE;
DROP TABLE IF EXISTS product_variants CASCADE;
DROP TABLE IF EXISTS products         CASCADE;
DROP TABLE IF EXISTS categories       CASCADE;
DROP TABLE IF EXISTS addresses        CASCADE;
DROP TABLE IF EXISTS customers        CASCADE;

-- ---------------------------------------------------------------------
-- 1. CUSTOMERS — people who shop on ShopNaija
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id   SERIAL       PRIMARY KEY,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    phone         VARCHAR(20)  NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_customer_email CHECK (email LIKE '%_@_%._%')
);

-- ---------------------------------------------------------------------
-- 2. ADDRESSES — a customer can have many delivery addresses
-- ---------------------------------------------------------------------
CREATE TABLE addresses (
    address_id    SERIAL       PRIMARY KEY,
    customer_id   INT          NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    label         VARCHAR(30)  NOT NULL DEFAULT 'Home',      -- Home, Office, ...
    street        VARCHAR(150) NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    state         VARCHAR(40)  NOT NULL,
    is_default    BOOLEAN      NOT NULL DEFAULT FALSE
);
-- Business rule: each customer may have at most ONE default address
CREATE UNIQUE INDEX uq_one_default_address
    ON addresses (customer_id) WHERE is_default;

-- ---------------------------------------------------------------------
-- 3. CATEGORIES — product categories, can be nested (Electronics > Phones)
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    category_id        SERIAL      PRIMARY KEY,
    name               VARCHAR(60) NOT NULL UNIQUE,
    parent_category_id INT         REFERENCES categories(category_id) ON DELETE SET NULL,
    CONSTRAINT chk_category_not_own_parent CHECK (parent_category_id <> category_id)
);

-- ---------------------------------------------------------------------
-- 4. PRODUCTS — the general product (e.g. "Tecno Spark 20")
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id    SERIAL        PRIMARY KEY,
    category_id   INT           NOT NULL REFERENCES categories(category_id),
    name          VARCHAR(120)  NOT NULL,
    brand         VARCHAR(60),
    description   TEXT,
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. PRODUCT_VARIANTS — the exact thing a customer buys
--    (e.g. "Tecno Spark 20, 128GB, Black"). Attributes differ by
--    category, so they are stored as JSONB (see normalisation.md §5).
-- ---------------------------------------------------------------------
CREATE TABLE product_variants (
    variant_id    SERIAL        PRIMARY KEY,
    product_id    INT           NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    sku           VARCHAR(40)   NOT NULL UNIQUE,
    attributes    JSONB         NOT NULL DEFAULT '{}'::jsonb,
    price         NUMERIC(12,2) NOT NULL,
    CONSTRAINT chk_variant_price      CHECK (price > 0),
    CONSTRAINT chk_attributes_object  CHECK (jsonb_typeof(attributes) = 'object')
);

-- ---------------------------------------------------------------------
-- 6. INVENTORY — stock level for each variant (one row per variant)
-- ---------------------------------------------------------------------
CREATE TABLE inventory (
    variant_id        INT         PRIMARY KEY REFERENCES product_variants(variant_id) ON DELETE CASCADE,
    quantity_on_hand  INT         NOT NULL DEFAULT 0,
    reorder_level     INT         NOT NULL DEFAULT 10,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_stock_not_negative  CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_reorder_not_negative CHECK (reorder_level >= 0)
);

-- ---------------------------------------------------------------------
-- 7. ORDERS — one checkout by one customer
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id            SERIAL       PRIMARY KEY,
    customer_id         INT          NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    shipping_address_id INT          NOT NULL REFERENCES addresses(address_id),
    order_status        VARCHAR(20)  NOT NULL DEFAULT 'pending',
    order_date          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_order_status CHECK (order_status IN
        ('pending','paid','processing','shipped','delivered','cancelled'))
);

-- ---------------------------------------------------------------------
-- 8. ORDER_ITEMS — the lines inside an order (resolves orders M:N variants)
--    unit_price is the price AT THE TIME OF PURCHASE (see normalisation.md §4)
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id     INT           NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    variant_id   INT           NOT NULL REFERENCES product_variants(variant_id),
    quantity     INT           NOT NULL,
    unit_price   NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (order_id, variant_id),
    CONSTRAINT chk_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_item_price    CHECK (unit_price > 0)
);

-- ---------------------------------------------------------------------
-- 9. PAYMENTS — an order can have several attempts (e.g. failed, then successful)
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    payment_id      SERIAL        PRIMARY KEY,
    order_id        INT           NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    amount          NUMERIC(12,2) NOT NULL,
    payment_method  VARCHAR(20)   NOT NULL,
    payment_status  VARCHAR(20)   NOT NULL DEFAULT 'pending',
    reference       VARCHAR(40)   NOT NULL UNIQUE,
    paid_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_payment_amount CHECK (amount > 0),
    CONSTRAINT chk_payment_method CHECK (payment_method IN
        ('card','bank_transfer','pay_on_delivery','wallet')),
    CONSTRAINT chk_payment_status CHECK (payment_status IN
        ('pending','successful','failed','refunded'))
);

-- ---------------------------------------------------------------------
-- 10. DELIVERY_AGENTS — riders/drivers who deliver orders
-- ---------------------------------------------------------------------
CREATE TABLE delivery_agents (
    agent_id    SERIAL      PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    phone       VARCHAR(20)  NOT NULL UNIQUE,
    base_city   VARCHAR(60)  NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 11. SHIPMENTS — one shipment per order
-- ---------------------------------------------------------------------
CREATE TABLE shipments (
    shipment_id      SERIAL       PRIMARY KEY,
    order_id         INT          NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE CASCADE,
    agent_id         INT          REFERENCES delivery_agents(agent_id) ON DELETE SET NULL,
    tracking_number  VARCHAR(30)  NOT NULL UNIQUE,
    shipment_status  VARCHAR(20)  NOT NULL DEFAULT 'awaiting_dispatch',
    dispatched_at    TIMESTAMPTZ,
    delivered_at     TIMESTAMPTZ,
    CONSTRAINT chk_shipment_status CHECK (shipment_status IN
        ('awaiting_dispatch','in_transit','out_for_delivery','delivered','returned')),
    CONSTRAINT chk_delivery_after_dispatch CHECK (delivered_at IS NULL OR delivered_at >= dispatched_at)
);

-- ---------------------------------------------------------------------
-- 12. DELIVERY_EVENTS — tracking history ("Left Lagos hub", "Out for delivery")
-- ---------------------------------------------------------------------
CREATE TABLE delivery_events (
    event_id      BIGSERIAL    PRIMARY KEY,
    shipment_id   INT          NOT NULL REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    event_status  VARCHAR(20)  NOT NULL,
    location      VARCHAR(80)  NOT NULL,
    event_time    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    note          VARCHAR(200),
    CONSTRAINT chk_event_status CHECK (event_status IN
        ('awaiting_dispatch','in_transit','out_for_delivery','delivered','returned'))
);

-- NOTE: Apart from primary keys and UNIQUE columns (which PostgreSQL indexes
-- automatically), no performance indexes are created here ON PURPOSE.
-- Portfolio 2 measures queries BEFORE and AFTER adding indexes.
