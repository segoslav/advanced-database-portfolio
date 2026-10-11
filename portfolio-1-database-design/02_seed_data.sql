-- =====================================================================
-- ShopNaija Online Marketplace — Sample Data Generator
-- MIT 8103 Advanced Database Systems — Portfolio 1
--
-- Run this file SECOND (after 01_schema.sql), in the "shopnaija" database.
-- Generates simulated (fake) data using PostgreSQL's own generate_series()
-- and random(). No real people or real payments are involved.
--
-- Approximate volumes:
--   5,000 customers | ~8,700 addresses | 15 categories | 2,000 products
--   ~5,000 variants | 100,000 orders | ~250,000 order items
--   ~105,000 payments | ~85,000 shipments | ~240,000 delivery events
-- Takes roughly 30–90 seconds on a normal laptop.
-- =====================================================================

SELECT setseed(0.42);   -- same "random" data every time the script is run

-- ---------------------------------------------------------------------
-- Lookup lists used to build realistic Nigerian names and places
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_lists;
CREATE TEMP TABLE tmp_lists AS SELECT
  ARRAY['Adaeze','Chinedu','Ngozi','Emeka','Aisha','Ibrahim','Fatima','Musa',
        'Tunde','Funmilayo','Bisi','Segun','Kemi','Yusuf','Zainab','Obinna',
        'Amaka','Ifeanyi','Halima','Sani','Temitope','Femi','Uche','Hauwa',
        'Babatunde','Chiamaka','Nkechi','Abdullahi','Ruth','David','Grace',
        'Samuel','Blessing','Victor','Esther','Daniel','Mariam','Peter',
        'Joy','Olumide']                                           AS first_names,
  ARRAY['Okafor','Adeyemi','Bello','Okonkwo','Abubakar','Eze','Ogunleye',
        'Mohammed','Nwosu','Balogun','Usman','Obi','Adebayo','Lawal','Ibekwe',
        'Danjuma','Okoro','Afolabi','Garba','Uzor','Ojo','Aliyu','Chukwu',
        'Salami','Yakubu','Onyeka','Akinola','Suleiman','Ekwueme','Bakare']
                                                                   AS last_names,
  ARRAY['Lagos|Lagos','Ikeja|Lagos','Lekki|Lagos','Abuja|FCT','Gwarinpa|FCT',
        'Kano|Kano','Ibadan|Oyo','Port Harcourt|Rivers','Enugu|Enugu',
        'Kaduna|Kaduna','Benin City|Edo','Abeokuta|Ogun','Jos|Plateau',
        'Owerri|Imo','Ilorin|Kwara','Uyo|Akwa Ibom','Warri|Delta',
        'Onitsha|Anambra','Yola|Adamawa','Calabar|Cross River']    AS places,
  ARRAY['Adeola Odeku St','Ahmadu Bello Way','Allen Ave','Aminu Kano Cres',
        'Awolowo Rd','Herbert Macaulay Way','Ogui Rd','Ikwerre Rd','Ring Rd',
        'Murtala Mohammed Way','Independence Ave','Zik Ave','Unity Rd',
        'Market Rd','Station Rd']                                  AS streets;

-- ---------------------------------------------------------------------
-- 1. Customers (5,000)
-- ---------------------------------------------------------------------
INSERT INTO customers (first_name, last_name, email, phone, created_at)
SELECT fn, ln,
       lower(fn) || '.' || lower(ln) || g || '@example.com',
       '080' || lpad(g::text, 8, '0'),
       TIMESTAMPTZ '2024-01-01' + random() * INTERVAL '640 days'
FROM generate_series(1, 5000) AS g,
     tmp_lists,
     LATERAL (SELECT first_names[1 + floor(random()*array_length(first_names,1))::int + (g*0)] AS fn,
                     last_names [1 + floor(random()*array_length(last_names ,1))::int + (g*0)] AS ln) AS pick;

-- ---------------------------------------------------------------------
-- 2. Addresses (1–3 per customer; the first one is the default)
-- ---------------------------------------------------------------------
INSERT INTO addresses (customer_id, label, street, city, state, is_default)
SELECT c.customer_id,
       CASE WHEN a.n = 1 THEN 'Home' WHEN a.n = 2 THEN 'Office' ELSE 'Other' END,
       (1 + floor(random()*150))::int || ' ' || streets[1 + floor(random()*array_length(streets,1))::int],
       split_part(place, '|', 1),
       split_part(place, '|', 2),
       a.n = 1
FROM customers c
CROSS JOIN tmp_lists
CROSS JOIN LATERAL generate_series(1, 1 + floor(random()*2.5)::int + (c.customer_id*0)) AS a(n)
CROSS JOIN LATERAL (SELECT places[1 + floor(random()*array_length(places,1))::int + (a.n*0)] AS place) AS p;

-- ---------------------------------------------------------------------
-- 3. Categories (5 parents, 10 children)
-- ---------------------------------------------------------------------
INSERT INTO categories (name, parent_category_id) VALUES
 ('Electronics', NULL), ('Fashion', NULL), ('Home & Kitchen', NULL),
 ('Groceries', NULL),   ('Health & Beauty', NULL);

INSERT INTO categories (name, parent_category_id)
SELECT v.name, c.category_id
FROM (VALUES ('Phones','Electronics'), ('Laptops','Electronics'),
             ('Men''s Clothing','Fashion'), ('Women''s Clothing','Fashion'), ('Shoes','Fashion'),
             ('Kitchen Appliances','Home & Kitchen'), ('Furniture','Home & Kitchen'),
             ('Beverages','Groceries'), ('Food Staples','Groceries'),
             ('Skincare','Health & Beauty')) AS v(name, parent)
JOIN categories c ON c.name = v.parent;

-- ---------------------------------------------------------------------
-- 4. Products (2,000) — placed only in the 10 child categories
-- ---------------------------------------------------------------------
INSERT INTO products (category_id, name, brand, description, created_at)
SELECT cat.category_id,
       cat.brand || ' ' || cat.item || ' ' || (100 + g),
       cat.brand,
       'Simulated product for the ShopNaija case study.',
       TIMESTAMPTZ '2024-01-01' + random() * INTERVAL '600 days'
FROM generate_series(1, 2000) AS g
CROSS JOIN LATERAL (
    SELECT c.category_id, b.brand, b.item
    FROM categories c
    JOIN (VALUES
        ('Phones',            ARRAY['Tecno','Infinix','Samsung','itel'],          'Smartphone'),
        ('Laptops',           ARRAY['HP','Lenovo','Dell','Asus'],                 'Laptop'),
        ('Men''s Clothing',   ARRAY['Ankara House','Mai Atafo','Zara'],           'Shirt'),
        ('Women''s Clothing', ARRAY['Ankara House','Lisa Folawiyo','Zara'],       'Dress'),
        ('Shoes',             ARRAY['Nike','Adidas','Aba Made'],                  'Sneakers'),
        ('Kitchen Appliances',ARRAY['Binatone','Scanfrost','Thermocool'],         'Blender'),
        ('Furniture',         ARRAY['Dufil Home','Vitafoam','Mouka'],             'Chair'),
        ('Beverages',         ARRAY['Milo','Peak','Lipton','Bournvita'],          'Pack'),
        ('Food Staples',      ARRAY['Mama Gold','Golden Penny','Dangote'],        'Bag'),
        ('Skincare',          ARRAY['Nivea','Dudu Osun','Zaron'],                 'Cream')
    ) AS x(cat, brands, item) ON x.cat = c.name
    CROSS JOIN LATERAL (SELECT brands[1 + floor(random()*array_length(brands,1))::int] AS brand, x.item) AS b
    ORDER BY random() + (g*0)
    LIMIT 1
) AS cat;

-- ---------------------------------------------------------------------
-- 5. Product variants (1–4 per product) with category-specific JSONB attributes
-- ---------------------------------------------------------------------
INSERT INTO product_variants (product_id, sku, attributes, price)
SELECT p.product_id,
       'SKU-' || p.product_id || '-' || v.n,
       CASE parent.name
         WHEN 'Electronics' THEN jsonb_build_object(
              'colour',  (ARRAY['Black','Blue','Silver','Gold'])[1 + floor(random()*4)::int],
              'storage_gb', (ARRAY[64,128,256,512])[1 + floor(random()*4)::int],
              'ram_gb',  (ARRAY[4,8,16])[1 + floor(random()*3)::int])
         WHEN 'Fashion' THEN jsonb_build_object(
              'size',    (ARRAY['S','M','L','XL','40','42','44'])[1 + floor(random()*7)::int],
              'colour',  (ARRAY['Black','White','Red','Green','Multicolour'])[1 + floor(random()*5)::int],
              'material',(ARRAY['Cotton','Ankara','Leather','Polyester'])[1 + floor(random()*4)::int])
         WHEN 'Home & Kitchen' THEN jsonb_build_object(
              'colour',  (ARRAY['White','Black','Brown','Grey'])[1 + floor(random()*4)::int],
              'warranty_months', (ARRAY[6,12,24])[1 + floor(random()*3)::int])
         WHEN 'Groceries' THEN jsonb_build_object(
              'weight',  (ARRAY['500g','1kg','5kg','10kg','25kg'])[1 + floor(random()*5)::int],
              'expiry_months', (ARRAY[6,12,18])[1 + floor(random()*3)::int])
         ELSE jsonb_build_object(
              'volume_ml', (ARRAY[100,200,400])[1 + floor(random()*3)::int],
              'skin_type', (ARRAY['All','Dry','Oily'])[1 + floor(random()*3)::int])
       END,
       round((CASE parent.name
                WHEN 'Electronics'    THEN 80000 + random()*900000
                WHEN 'Fashion'        THEN 5000  + random()*60000
                WHEN 'Home & Kitchen' THEN 15000 + random()*250000
                WHEN 'Groceries'      THEN 1500  + random()*40000
                ELSE                       2000  + random()*25000
              END)::numeric, -2)
FROM products p
JOIN categories child  ON child.category_id  = p.category_id
JOIN categories parent ON parent.category_id = child.parent_category_id
CROSS JOIN LATERAL generate_series(1, 1 + floor(random()*4)::int + (p.product_id*0)) AS v(n);

-- ---------------------------------------------------------------------
-- 6. Inventory (one row per variant; about 5% are low on stock)
-- ---------------------------------------------------------------------
INSERT INTO inventory (variant_id, quantity_on_hand, reorder_level)
SELECT variant_id,
       CASE WHEN random() < 0.05 THEN floor(random()*10)::int
            ELSE 20 + floor(random()*480)::int END,
       10
FROM product_variants;

-- ---------------------------------------------------------------------
-- 7. Delivery agents (60)
-- ---------------------------------------------------------------------
INSERT INTO delivery_agents (full_name, phone, base_city)
SELECT first_names[1 + floor(random()*array_length(first_names,1))::int + (g*0)] || ' ' ||
       last_names [1 + floor(random()*array_length(last_names ,1))::int],
       '090' || lpad(g::text, 8, '0'),
       split_part(places[1 + floor(random()*array_length(places,1))::int], '|', 1)
FROM generate_series(1, 60) AS g, tmp_lists;

-- ---------------------------------------------------------------------
-- 8. Orders (100,000) between Apr 2025 and Oct 2026.
--    Older orders are mostly delivered; recent ones are still in progress.
-- ---------------------------------------------------------------------
INSERT INTO orders (customer_id, shipping_address_id, order_status, order_date)
SELECT c.customer_id, a.address_id,
       CASE
         WHEN o.order_date < TIMESTAMPTZ '2026-09-25' THEN
              CASE WHEN r < 0.90 THEN 'delivered' ELSE 'cancelled' END
         ELSE (ARRAY['pending','paid','processing','shipped','delivered','cancelled'])
              [1 + floor(r*6)::int]
       END,
       o.order_date
FROM generate_series(1, 100000) AS g
CROSS JOIN LATERAL (SELECT 1 + floor(random()*5000)::int + (g*0) AS cid,
                           random() + (g*0) AS r,
                           TIMESTAMPTZ '2025-04-01' + random() * INTERVAL '557 days' + (g*0) * INTERVAL '1 s' AS order_date) AS o
JOIN customers c ON c.customer_id = o.cid
JOIN addresses a ON a.customer_id = c.customer_id AND a.is_default;

-- ---------------------------------------------------------------------
-- 9. Order items (1–4 different variants per order)
--    unit_price = the variant's current price (price at time of purchase)
-- ---------------------------------------------------------------------
INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT o.order_id, pv.variant_id, 1 + floor(random()*3)::int, pv.price
FROM orders o
CROSS JOIN LATERAL generate_series(1, 1 + floor(random()*4)::int + (o.order_id*0)) AS i(n)
CROSS JOIN LATERAL (SELECT 1 + floor(random()*(SELECT max(variant_id) FROM product_variants))::int + (i.n*0) AS vid) AS pick
JOIN product_variants pv ON pv.variant_id = pick.vid
ON CONFLICT (order_id, variant_id) DO NOTHING;   -- skip if the same variant was picked twice

-- ---------------------------------------------------------------------
-- 10. Payments
--     ~5% of orders have a failed attempt first, then a successful one.
--     Cancelled orders: one failed or refunded payment. Pending: one pending.
-- ---------------------------------------------------------------------
WITH totals AS (
    SELECT o.order_id, o.order_status, o.order_date, SUM(oi.quantity * oi.unit_price) AS total
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id
)
INSERT INTO payments (order_id, amount, payment_method, payment_status, reference, paid_at)
SELECT t.order_id, t.total,
       (ARRAY['card','bank_transfer','pay_on_delivery','wallet'])[1 + floor(random()*4)::int],
       CASE WHEN t.order_status = 'pending'   THEN 'pending'
            WHEN t.order_status = 'cancelled' THEN CASE WHEN random() < 0.5 THEN 'failed' ELSE 'refunded' END
            ELSE 'successful' END,
       'PAY-' || lpad(t.order_id::text, 7, '0') || '-A',
       t.order_date + INTERVAL '5 minutes'
FROM totals t;

-- Earlier failed attempts for ~5% of successful payments
INSERT INTO payments (order_id, amount, payment_method, payment_status, reference, paid_at)
SELECT order_id, amount, 'card', 'failed',
       'PAY-' || lpad(order_id::text, 7, '0') || '-F',
       paid_at - INTERVAL '3 minutes'
FROM payments
WHERE payment_status = 'successful' AND random() < 0.05;

-- ---------------------------------------------------------------------
-- 11. Shipments — for orders that have been shipped or delivered
-- ---------------------------------------------------------------------
INSERT INTO shipments (order_id, agent_id, tracking_number, shipment_status, dispatched_at, delivered_at)
SELECT o.order_id,
       1 + floor(random()*60)::int,
       'SNG' || lpad(o.order_id::text, 9, '0'),
       CASE o.order_status WHEN 'shipped' THEN 'in_transit' ELSE 'delivered' END,
       o.order_date + d.dispatch_delay,
       CASE WHEN o.order_status = 'delivered'
            THEN o.order_date + d.dispatch_delay + d.transit_time END
FROM orders o
CROSS JOIN LATERAL (SELECT INTERVAL '1 hour' * (6 + floor(random()*42) + o.order_id*0) AS dispatch_delay,
                           INTERVAL '1 hour' * (12 + floor(random()*120) + o.order_id*0) AS transit_time) AS d
WHERE o.order_status IN ('shipped','delivered');

-- ---------------------------------------------------------------------
-- 12. Delivery events — the tracking history for each shipment
-- ---------------------------------------------------------------------
INSERT INTO delivery_events (shipment_id, event_status, location, event_time, note)
SELECT s.shipment_id, 'in_transit', 'ShopNaija Hub, Lagos', s.dispatched_at, 'Package dispatched from hub'
FROM shipments s;

INSERT INTO delivery_events (shipment_id, event_status, location, event_time, note)
SELECT s.shipment_id, 'out_for_delivery', a.city, s.delivered_at - INTERVAL '3 hours', 'Rider is on the way'
FROM shipments s
JOIN orders o    ON o.order_id = s.order_id
JOIN addresses a ON a.address_id = o.shipping_address_id
WHERE s.shipment_status = 'delivered';

INSERT INTO delivery_events (shipment_id, event_status, location, event_time, note)
SELECT s.shipment_id, 'delivered', a.city, s.delivered_at, 'Delivered to customer'
FROM shipments s
JOIN orders o    ON o.order_id = s.order_id
JOIN addresses a ON a.address_id = o.shipping_address_id
WHERE s.shipment_status = 'delivered';

-- ---------------------------------------------------------------------
-- Refresh planner statistics so Portfolio 2 execution plans are accurate
-- ---------------------------------------------------------------------
ANALYZE;

-- Quick summary of what was created
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'addresses',        COUNT(*) FROM addresses
UNION ALL SELECT 'categories',       COUNT(*) FROM categories
UNION ALL SELECT 'products',         COUNT(*) FROM products
UNION ALL SELECT 'product_variants', COUNT(*) FROM product_variants
UNION ALL SELECT 'inventory',        COUNT(*) FROM inventory
UNION ALL SELECT 'orders',           COUNT(*) FROM orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM payments
UNION ALL SELECT 'delivery_agents',  COUNT(*) FROM delivery_agents
UNION ALL SELECT 'shipments',        COUNT(*) FROM shipments
UNION ALL SELECT 'delivery_events',  COUNT(*) FROM delivery_events;
