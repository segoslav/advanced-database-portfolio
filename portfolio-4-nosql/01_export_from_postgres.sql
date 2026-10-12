-- =====================================================================
-- ShopNaija — Export the relational data as MongoDB-ready JSON documents
-- MIT 8103 Advanced Database Systems — Portfolio 4
--
-- Run in SQL Shell (psql) from inside the portfolio-4-nosql folder:
--     \cd 'C:/Users/<you>/.../portfolio-4-nosql'
--     \i 01_export_from_postgres.sql
--
-- This is where the data model changes. Rows that SQL keeps in 12 separate
-- tables are folded together into 3 kinds of self-contained document:
--   products   <- products + categories + product_variants + inventory
--   customers  <- customers + addresses
--   orders     <- orders + order_items + payments + shipments
--                 + delivery_agents + delivery_events
-- Output: one JSON document per line ("JSON Lines") in the data/ folder.
-- The data/ folder is large (~150 MB) and is NOT committed to GitHub
-- (see .gitignore); this script can recreate it at any time.
-- =====================================================================

\encoding UTF8
\pset pager off
\pset format unaligned
\pset tuples_only on

-- ---------------------------------------------------------------------
-- 1. PRODUCTS: each product embeds its category and all its variants,
--    and each variant embeds its own stock level.
-- ---------------------------------------------------------------------
\qecho 'Exporting products...'
\o data/products.jsonl
WITH variants AS (
    SELECT v.product_id,
           json_agg(json_build_object(
               'sku',        v.sku,
               'attributes', v.attributes,
               'price',      v.price,
               'stock',      json_build_object('on_hand',       i.quantity_on_hand,
                                               'reorder_level', i.reorder_level)
           ) ORDER BY v.variant_id) AS variants
    FROM product_variants v
    JOIN inventory i ON i.variant_id = v.variant_id
    GROUP BY v.product_id
)
SELECT json_build_object(
           '_id',         p.product_id,
           'name',        p.name,
           'brand',       p.brand,
           'description', p.description,
           'is_active',   p.is_active,
           'created_at',  p.created_at,
           'category',    json_build_object('name', child.name, 'parent', parent.name),
           'variants',    COALESCE(v.variants, '[]'::json)
       )
FROM products p
JOIN categories child        ON child.category_id  = p.category_id
LEFT JOIN categories parent  ON parent.category_id = child.parent_category_id
LEFT JOIN variants v         ON v.product_id       = p.product_id
ORDER BY p.product_id;
\o

-- ---------------------------------------------------------------------
-- 2. CUSTOMERS: each customer embeds their list of addresses.
-- ---------------------------------------------------------------------
\qecho 'Exporting customers...'
\o data/customers.jsonl
WITH addr AS (
    SELECT customer_id,
           json_agg(json_build_object(
               'address_id', address_id,
               'label',      label,
               'street',     street,
               'city',       city,
               'state',      state,
               'is_default', is_default
           ) ORDER BY address_id) AS addresses
    FROM addresses
    GROUP BY customer_id
)
SELECT json_build_object(
           '_id',        c.customer_id,
           'first_name', c.first_name,
           'last_name',  c.last_name,
           'email',      c.email,
           'phone',      c.phone,
           'created_at', c.created_at,
           'addresses',  COALESCE(a.addresses, '[]'::json)
       )
FROM customers c
LEFT JOIN addr a ON a.customer_id = c.customer_id
ORDER BY c.customer_id;
\o

-- ---------------------------------------------------------------------
-- 3. ORDERS: each order is a complete record of one checkout. It embeds
--    its items, payments, shipment and tracking events, plus SNAPSHOTS of
--    the customer name, delivery address and product details as they were
--    when the order was placed.
-- ---------------------------------------------------------------------
\qecho 'Exporting orders (about a minute)...'
\o data/orders.jsonl
WITH items AS (
    SELECT oi.order_id,
           json_agg(json_build_object(
               'sku',          v.sku,
               'product_id',   p.product_id,
               'product_name', p.name,
               'category',     parent.name,
               'subcategory',  child.name,
               'quantity',     oi.quantity,
               'unit_price',   oi.unit_price
           ) ORDER BY v.sku) AS items,
           SUM(oi.quantity * oi.unit_price) AS total
    FROM order_items oi
    JOIN product_variants v ON v.variant_id    = oi.variant_id
    JOIN products p         ON p.product_id    = v.product_id
    JOIN categories child   ON child.category_id  = p.category_id
    LEFT JOIN categories parent ON parent.category_id = child.parent_category_id
    GROUP BY oi.order_id
),
pays AS (
    SELECT order_id,
           json_agg(json_build_object(
               'method',    payment_method,
               'status',    payment_status,
               'amount',    amount,
               'reference', reference,
               'paid_at',   paid_at
           ) ORDER BY paid_at) AS payments
    FROM payments
    GROUP BY order_id
),
events AS (
    SELECT shipment_id,
           json_agg(json_build_object(
               'status',   event_status,
               'location', location,
               'time',     event_time,
               'note',     note
           ) ORDER BY event_time) AS events
    FROM delivery_events
    GROUP BY shipment_id
),
ships AS (
    SELECT s.order_id,
           json_build_object(
               'tracking_number', s.tracking_number,
               'status',          s.shipment_status,
               'agent',           json_build_object('name', da.full_name, 'phone', da.phone),
               'dispatched_at',   s.dispatched_at,
               'delivered_at',    s.delivered_at,
               'events',          COALESCE(e.events, '[]'::json)
           ) AS shipment
    FROM shipments s
    LEFT JOIN delivery_agents da ON da.agent_id   = s.agent_id
    LEFT JOIN events e           ON e.shipment_id = s.shipment_id
)
SELECT json_build_object(
           '_id',              o.order_id,
           'customer_id',      o.customer_id,
           'customer_name',    c.first_name || ' ' || c.last_name,
           'status',           o.order_status,
           'order_date',       o.order_date,
           'shipping_address', json_build_object('street', a.street, 'city', a.city, 'state', a.state),
           'items',            COALESCE(i.items, '[]'::json),
           'total',            COALESCE(i.total, 0),
           'payments',         COALESCE(py.payments, '[]'::json),
           'shipment',         sh.shipment
       )
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id
JOIN addresses a   ON a.address_id  = o.shipping_address_id
LEFT JOIN items i  ON i.order_id    = o.order_id
LEFT JOIN pays py  ON py.order_id   = o.order_id
LEFT JOIN ships sh ON sh.order_id   = o.order_id
ORDER BY o.order_id;
\o

-- Back to normal display
\pset format aligned
\pset tuples_only off
\qecho 'Done. Three files written to the data folder.'
