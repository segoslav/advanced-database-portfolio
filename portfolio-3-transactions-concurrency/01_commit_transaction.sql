-- =====================================================================
-- ShopNaija — Demo 1: a successful "place order" transaction (COMMIT)
-- MIT 8103 Advanced Database Systems — Portfolio 3
--
-- Run in SQL Shell (psql). Placing an order touches FOUR tables. They must
-- all succeed together or not at all (Atomicity), and stock may never go
-- below zero (Consistency, enforced by the CHECK constraint).
-- =====================================================================

\qecho '--- BEFORE: stock of SKU-1-1 ---'
SELECT v.sku, i.quantity_on_hand
FROM inventory i JOIN product_variants v USING (variant_id)
WHERE v.sku = 'SKU-1-1';

BEGIN;

\qecho '--- Step 1: create the order (status pending) ---'
INSERT INTO orders (customer_id, shipping_address_id, order_status)
SELECT 1, address_id, 'pending' FROM addresses
WHERE customer_id = 1 AND is_default
RETURNING order_id \gset

\qecho '--- Step 2: add 2 units of SKU-1-1 at the current price ---'
INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT :order_id, variant_id, 2, price
FROM product_variants WHERE sku = 'SKU-1-1';

\qecho '--- Step 3: reduce stock by 2 ---'
UPDATE inventory
SET quantity_on_hand = quantity_on_hand - 2, updated_at = now()
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-1-1');

\qecho '--- Step 4: record a successful card payment for the order total ---'
INSERT INTO payments (order_id, amount, payment_method, payment_status, reference)
SELECT :order_id, SUM(quantity * unit_price), 'card', 'successful', 'PAY-DEMO-' || :order_id
FROM order_items WHERE order_id = :order_id;

\qecho '--- Step 5: mark the order as paid ---'
UPDATE orders SET order_status = 'paid' WHERE order_id = :order_id;

COMMIT;

\qecho '--- AFTER COMMIT: the order, its payment, and the new stock level ---'
SELECT o.order_id, o.order_status, p.amount, p.payment_status, p.reference
FROM orders o JOIN payments p USING (order_id)
WHERE o.order_id = :order_id;

SELECT v.sku, i.quantity_on_hand
FROM inventory i JOIN product_variants v USING (variant_id)
WHERE v.sku = 'SKU-1-1';
