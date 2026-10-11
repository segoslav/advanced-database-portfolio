-- =====================================================================
-- ShopNaija — Constraint Tests (evidence that the rules actually work)
-- MIT 8103 Advanced Database Systems — Portfolio 1
--
-- Run this file THIRD. Each test deliberately tries to insert BAD data.
-- A passing test prints:   PASS: ... was rejected
-- Nothing is saved: every bad insert is rejected by the database.
-- In pgAdmin the results appear in the "Messages" tab.
-- =====================================================================

DO $$
BEGIN
    -- Test 1: duplicate customer email (UNIQUE)
    BEGIN
        INSERT INTO customers (first_name, last_name, email, phone)
        SELECT 'Test', 'User', email, '07099999999' FROM customers LIMIT 1;
        RAISE NOTICE 'FAIL: duplicate email was accepted';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: duplicate customer email was rejected (UNIQUE)';
    END;

    -- Test 2: badly formatted email (CHECK)
    BEGIN
        INSERT INTO customers (first_name, last_name, email, phone)
        VALUES ('Test', 'User', 'not-an-email', '07099999998');
        RAISE NOTICE 'FAIL: invalid email was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: invalid email format was rejected (CHECK chk_customer_email)';
    END;

    -- Test 3: order for a customer who does not exist (FOREIGN KEY)
    BEGIN
        INSERT INTO orders (customer_id, shipping_address_id) VALUES (999999, 1);
        RAISE NOTICE 'FAIL: order for missing customer was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS: order for non-existent customer was rejected (FOREIGN KEY)';
    END;

    -- Test 4: negative stock (CHECK)
    BEGIN
        UPDATE inventory SET quantity_on_hand = -5 WHERE variant_id = 1;
        RAISE NOTICE 'FAIL: negative stock was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: negative stock was rejected (CHECK chk_stock_not_negative)';
    END;

    -- Test 5: zero or negative price (CHECK)
    BEGIN
        INSERT INTO product_variants (product_id, sku, price) VALUES (1, 'SKU-TEST-0', 0);
        RAISE NOTICE 'FAIL: zero price was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: zero price was rejected (CHECK chk_variant_price)';
    END;

    -- Test 6: invalid order status (CHECK)
    BEGIN
        UPDATE orders SET order_status = 'lost_in_space' WHERE order_id = 1;
        RAISE NOTICE 'FAIL: invalid order status was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: invalid order status was rejected (CHECK chk_order_status)';
    END;

    -- Test 7: same product variant twice in one order (composite PRIMARY KEY)
    BEGIN
        INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
        SELECT order_id, variant_id, 1, unit_price FROM order_items LIMIT 1;
        RAISE NOTICE 'FAIL: duplicate order line was accepted';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: duplicate order line was rejected (PRIMARY KEY order_id + variant_id)';
    END;

    -- Test 8: second default address for the same customer (partial UNIQUE index)
    BEGIN
        INSERT INTO addresses (customer_id, street, city, state, is_default)
        VALUES (1, '1 Test St', 'Abuja', 'FCT', TRUE);
        RAISE NOTICE 'FAIL: second default address was accepted';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: second default address was rejected (UNIQUE INDEX uq_one_default_address)';
    END;

    -- Test 9: delivered before it was dispatched (CHECK)
    BEGIN
        UPDATE shipments SET delivered_at = dispatched_at - INTERVAL '1 day'
        WHERE shipment_id = 1;
        RAISE NOTICE 'FAIL: delivery before dispatch was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: delivery date before dispatch date was rejected (CHECK chk_delivery_after_dispatch)';
    END;

    -- Test 10: product attributes that are not a JSON object (CHECK)
    BEGIN
        INSERT INTO product_variants (product_id, sku, attributes, price)
        VALUES (1, 'SKU-TEST-1', '["red","blue"]'::jsonb, 5000);
        RAISE NOTICE 'FAIL: non-object attributes were accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS: attributes that are not a JSON object were rejected (CHECK chk_attributes_object)';
    END;

    -- Test 11: deleting a customer who has orders (ON DELETE RESTRICT)
    BEGIN
        DELETE FROM customers WHERE customer_id = (SELECT customer_id FROM orders LIMIT 1);
        RAISE NOTICE 'FAIL: customer with orders was deleted';
    -- PostgreSQL may report this as restrict_violation (23001) or
    -- foreign_key_violation (23503) depending on version, so accept both.
    EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN
        RAISE NOTICE 'PASS: deleting a customer who has orders was blocked (ON DELETE RESTRICT)';
    END;
END $$;
