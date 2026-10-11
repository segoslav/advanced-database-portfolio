-- =====================================================================
-- ShopNaija — Business queries with execution plans
-- MIT 8103 Advanced Database Systems — Portfolio 2
--
-- Run this file TWICE in total:
--   1. BEFORE 02_create_indexes.sql  -> save output as results/before_plans.txt
--   2. AFTER  02_create_indexes.sql  -> save output as results/after_plans.txt
--
-- Designed for SQL Shell (psql). The \qecho lines print headings into
-- the saved output. In pgAdmin, highlight ONE query (from EXPLAIN to ;)
-- and press F5 instead of running the whole file.
--
-- EXPLAIN (ANALYZE, BUFFERS) really runs the query and reports:
--   - the plan the database chose (Seq Scan, Index Scan, ...)
--   - actual time taken and rows produced at each step
--   - buffers: how many 8KB data pages were read
-- =====================================================================

\qecho '=================================================================='
\qecho 'Q1  Customer order history (customer 2955, newest first)'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, order_status, order_date
FROM orders
WHERE customer_id = 2955
ORDER BY order_date DESC;

\qecho '=================================================================='
\qecho 'Q2  Track a delivery by tracking number'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.tracking_number, de.event_status, de.location, de.event_time, de.note
FROM shipments s
JOIN delivery_events de ON de.shipment_id = s.shipment_id
WHERE s.tracking_number = 'SNG000000001'
ORDER BY de.event_time;

\qecho '=================================================================='
\qecho 'Q3  Sales history of one product variant (variant 1234)'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, oi.quantity, oi.unit_price
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE oi.variant_id = 1234
ORDER BY o.order_date DESC;

\qecho '=================================================================='
\qecho 'Q4  Fulfilment queue: orders not yet shipped, oldest first'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_status, order_date
FROM orders
WHERE order_status IN ('pending','paid','processing')
ORDER BY order_date;

\qecho '=================================================================='
\qecho 'Q5  Case-insensitive customer lookup by email'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, first_name, last_name, phone
FROM customers
WHERE lower(email) = lower('Peter.Uzor4538@example.com');

\qecho '=================================================================='
\qecho 'Q6  Monthly revenue since 1 Aug 2026 (excluding cancelled orders)'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', o.order_date)::date AS month,
       COUNT(DISTINCT o.order_id)              AS orders,
       SUM(oi.quantity * oi.unit_price)        AS revenue_ngn
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_date >= '2026-08-01'
  AND o.order_status <> 'cancelled'
GROUP BY 1
ORDER BY 1;

\qecho '=================================================================='
\qecho 'Q7  Product search by attribute: 256GB storage AND 16GB RAM'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.name, v.sku, v.attributes, v.price
FROM product_variants v
JOIN products p ON p.product_id = v.product_id
WHERE v.attributes @> '{"storage_gb": 256, "ram_gb": 16}';

\qecho '=================================================================='
\qecho 'Q8  Low-stock alert (stock at or below reorder level)'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.variant_id, v.sku, i.quantity_on_hand, i.reorder_level
FROM inventory i
JOIN product_variants v ON v.variant_id = i.variant_id
WHERE i.quantity_on_hand <= i.reorder_level
ORDER BY i.quantity_on_hand;
