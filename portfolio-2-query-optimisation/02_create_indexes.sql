-- =====================================================================
-- ShopNaija — Optimisation: targeted indexes
-- MIT 8103 Advanced Database Systems — Portfolio 2
--
-- Run this AFTER you have recorded the "before" results of
-- 01_business_queries.sql. Each index targets one specific query.
-- =====================================================================

-- Q1  Customer order history
--     Composite index: finds one customer's orders AND returns them already
--     sorted newest-first, so no separate sort step is needed.
CREATE INDEX IF NOT EXISTS idx_orders_customer_date
    ON orders (customer_id, order_date DESC);

-- Q2  Track a delivery
--     PostgreSQL does NOT automatically index foreign keys. Without this,
--     finding one parcel's events means reading all ~264,000 events.
CREATE INDEX IF NOT EXISTS idx_delivery_events_shipment
    ON delivery_events (shipment_id, event_time);

-- Q3  Sales history of one product variant
--     The order_items primary key is (order_id, variant_id). It helps when
--     searching by order_id, but NOT by variant_id alone (wrong column first).
CREATE INDEX IF NOT EXISTS idx_order_items_variant
    ON order_items (variant_id);

-- Q4  Fulfilment queue (orders not yet shipped)
--     Partial index: only ~1.4% of orders are open, so the index stores
--     just those rows. Small, fast, and cheap to maintain.
CREATE INDEX IF NOT EXISTS idx_orders_open
    ON orders (order_date)
    WHERE order_status IN ('pending','paid','processing');

-- Q5  Case-insensitive customer lookup at login / support desk
--     Expression index: the existing UNIQUE index on email cannot be used
--     for lower(email), because the stored values are not lower-cased.
CREATE INDEX IF NOT EXISTS idx_customers_email_lower
    ON customers (lower(email));

-- Q6  Monthly revenue report for recent months
--     Range index on order date.
CREATE INDEX IF NOT EXISTS idx_orders_date
    ON orders (order_date);

-- Q7  Search products by attribute (e.g. 256GB phones with 16GB RAM)
--     GIN index: the index type designed for "contains" searches on JSONB.
CREATE INDEX IF NOT EXISTS idx_variants_attributes
    ON product_variants USING GIN (attributes jsonb_path_ops);

-- Q8  Low-stock alert — deliberately NOT indexed. See README §Analysis.

-- Refresh statistics so the planner knows the new indexes exist
ANALYZE;

-- List the indexes created (evidence)
SELECT tablename, indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
