-- =====================================================================
-- ShopNaija — Reset: remove the Portfolio 2 indexes and view
-- Only needed if you want to repeat the BEFORE measurements.
-- =====================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_daily_sales;
DROP INDEX IF EXISTS idx_orders_customer_date;
DROP INDEX IF EXISTS idx_delivery_events_shipment;
DROP INDEX IF EXISTS idx_order_items_variant;
DROP INDEX IF EXISTS idx_orders_open;
DROP INDEX IF EXISTS idx_customers_email_lower;
DROP INDEX IF EXISTS idx_orders_date;
DROP INDEX IF EXISTS idx_variants_attributes;
ANALYZE;
