-- =====================================================================
-- ShopNaija — Demo 2: ROLLBACK and SAVEPOINT
-- MIT 8103 Advanced Database Systems — Portfolio 3
--
-- Run in SQL Shell (psql). Three scenarios:
--   2A  Card declined -> the shop cancels the whole order (explicit ROLLBACK)
--   2B  Customer orders more than is in stock -> the database itself
--       refuses, the transaction is aborted, and nothing is saved
--   2C  First payment attempt fails -> undo ONLY the payment step with a
--       SAVEPOINT, retry with bank transfer, and keep the order
-- ERROR messages in 2B and 2C are EXPECTED; they are part of the demo.
-- =====================================================================

\qecho '=================================================================='
\qecho '2A  Card declined: explicit ROLLBACK'
\qecho '=================================================================='
SELECT quantity_on_hand AS stock_before FROM inventory
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-2-1');

BEGIN;
INSERT INTO orders (customer_id, shipping_address_id)
SELECT 2, address_id FROM addresses WHERE customer_id = 2 AND is_default
RETURNING order_id AS order_2a \gset

INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT :order_2a, variant_id, 1, price FROM product_variants WHERE sku = 'SKU-2-1';

UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-2-1');

\qecho 'Inside the transaction, the stock HAS been reduced:'
SELECT quantity_on_hand AS stock_inside_transaction FROM inventory
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-2-1');

\qecho 'Payment gateway says: CARD DECLINED -> ROLLBACK everything'
ROLLBACK;

\qecho 'After ROLLBACK: the order does not exist and stock is back to where it was'
SELECT COUNT(*) AS orders_found FROM orders WHERE order_id = :order_2a;
SELECT quantity_on_hand AS stock_after_rollback FROM inventory
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-2-1');

\qecho '=================================================================='
\qecho '2B  Ordering more than is in stock: the CHECK constraint aborts it'
\qecho '=================================================================='
SELECT quantity_on_hand AS stock_before FROM inventory
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-3-1');

BEGIN;
INSERT INTO orders (customer_id, shipping_address_id)
SELECT 3, address_id FROM addresses WHERE customer_id = 3 AND is_default
RETURNING order_id AS order_2b \gset

INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT :order_2b, variant_id, 1000, price FROM product_variants WHERE sku = 'SKU-3-1';

\qecho 'Reducing stock by 1000 (more than exists). EXPECT an ERROR:'
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1000
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-3-1');

\qecho 'The transaction is now aborted. Any further command is refused. EXPECT an ERROR:'
SELECT 'this will not run';

ROLLBACK;

\qecho 'After ROLLBACK: the half-created order was discarded, stock unchanged'
SELECT COUNT(*) AS orders_found FROM orders WHERE order_id = :order_2b;
SELECT quantity_on_hand AS stock_after FROM inventory
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-3-1');

\qecho '=================================================================='
\qecho '2C  SAVEPOINT: retry a failed payment without losing the order'
\qecho '=================================================================='
BEGIN;
INSERT INTO orders (customer_id, shipping_address_id)
SELECT 4, address_id FROM addresses WHERE customer_id = 4 AND is_default
RETURNING order_id AS order_2c \gset

INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT :order_2c, variant_id, 1, price FROM product_variants WHERE sku = 'SKU-4-1';

UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1
WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-4-1');

SAVEPOINT before_payment;

\qecho 'Attempt 1: card gateway returns an amount of 0 (invalid). EXPECT an ERROR:'
INSERT INTO payments (order_id, amount, payment_method, payment_status, reference)
VALUES (:order_2c, 0, 'card', 'successful', 'PAY-DEMO-' || :order_2c || '-1');

\qecho 'Undo ONLY the failed payment step:'
ROLLBACK TO SAVEPOINT before_payment;

\qecho 'Attempt 2: bank transfer for the correct amount'
INSERT INTO payments (order_id, amount, payment_method, payment_status, reference)
SELECT :order_2c, SUM(quantity * unit_price), 'bank_transfer', 'successful', 'PAY-DEMO-' || :order_2c || '-2'
FROM order_items WHERE order_id = :order_2c;

UPDATE orders SET order_status = 'paid' WHERE order_id = :order_2c;
COMMIT;

\qecho 'Result: the order survived, with only the successful payment recorded'
SELECT o.order_id, o.order_status, p.payment_method, p.amount, p.reference
FROM orders o JOIN payments p USING (order_id)
WHERE o.order_id = :order_2c;

\qecho '=================================================================='
\qecho 'Side note: order numbers used by rolled-back transactions are skipped'
\qecho '=================================================================='
SELECT :order_2a AS rolled_back_2a, :order_2b AS rolled_back_2b, :order_2c AS committed_2c;
