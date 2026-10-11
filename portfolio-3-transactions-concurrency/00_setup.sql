-- =====================================================================
-- ShopNaija — Portfolio 3 setup: the "last phone in stock" flash sale
-- MIT 8103 Advanced Database Systems — Portfolio 3
--
-- Run ONCE before the demos. Safe to re-run.
-- Creates:
--   * a flash-sale product with exactly ONE unit in stock
--   * a version column on inventory (for optimistic locking)
--   * small helper functions so the two-window demos stay short
-- =====================================================================

-- 1. Version column for optimistic locking (Demo 3)
ALTER TABLE inventory ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;

-- 2. Flash-sale product and variant
INSERT INTO products (category_id, name, brand, description)
SELECT category_id, 'Tecno Phantom X Flash Sale', 'Tecno', 'Flash sale: only one unit available'
FROM categories WHERE name = 'Phones'
AND NOT EXISTS (SELECT 1 FROM products WHERE name = 'Tecno Phantom X Flash Sale');

INSERT INTO product_variants (product_id, sku, attributes, price)
SELECT product_id, 'FLASH-001', '{"colour":"Black","storage_gb":256,"ram_gb":8}', 250000
FROM products WHERE name = 'Tecno Phantom X Flash Sale'
ON CONFLICT (sku) DO NOTHING;

INSERT INTO inventory (variant_id, quantity_on_hand, reorder_level)
SELECT variant_id, 1, 0 FROM product_variants WHERE sku = 'FLASH-001'
ON CONFLICT (variant_id) DO NOTHING;

-- 3. Helper: the flash-sale variant's id
CREATE OR REPLACE FUNCTION flash_id() RETURNS INT
LANGUAGE sql STABLE AS
$$ SELECT variant_id FROM product_variants WHERE sku = 'FLASH-001' $$;

-- 4. Helper: record a paid order for ONE flash-sale phone.
--    Deliberately does NOT touch stock: checking and reducing stock is
--    what each demo does by hand, so you can see where things go wrong.
CREATE OR REPLACE FUNCTION record_flash_order(p_customer INT) RETURNS INT
LANGUAGE plpgsql AS
$$
DECLARE v_order INT;
BEGIN
    INSERT INTO orders (customer_id, shipping_address_id, order_status)
    SELECT p_customer, address_id, 'paid'
    FROM addresses WHERE customer_id = p_customer AND is_default
    RETURNING order_id INTO v_order;

    INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
    SELECT v_order, variant_id, 1, price FROM product_variants WHERE sku = 'FLASH-001';

    RETURN v_order;
END;
$$;

-- 5. Helper view: stock left vs phones sold. Oversold if sold > 1.
CREATE OR REPLACE VIEW flash_sale_status AS
SELECT i.quantity_on_hand                       AS stock_left,
       i.version,
       (SELECT COUNT(*) FROM order_items oi
         WHERE oi.variant_id = i.variant_id)    AS phones_sold,
       CASE WHEN (SELECT COUNT(*) FROM order_items oi
                   WHERE oi.variant_id = i.variant_id) > 1
            THEN 'OVERSOLD!' ELSE 'OK' END       AS verdict
FROM inventory i
WHERE i.variant_id = flash_id();

-- 6. Helper: put the flash sale back to its starting state between demos
CREATE OR REPLACE FUNCTION reset_flash_sale() RETURNS TEXT
LANGUAGE plpgsql AS
$$
BEGIN
    DELETE FROM orders WHERE order_id IN
        (SELECT order_id FROM order_items WHERE variant_id = flash_id());
    UPDATE inventory SET quantity_on_hand = 1, version = 1, updated_at = now()
    WHERE variant_id = flash_id();
    RETURN 'Flash sale reset: 1 phone in stock, 0 sold';
END;
$$;

SELECT reset_flash_sale();
SELECT * FROM flash_sale_status;
