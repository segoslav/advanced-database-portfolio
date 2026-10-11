-- =====================================================================
-- ShopNaija — Optimisation beyond indexes: a materialised view
-- MIT 8103 Advanced Database Systems — Portfolio 2
--
-- Q6 (monthly revenue) barely improved with an index, because it must
-- still read and join ~250,000 order_items rows every time it runs.
-- A materialised view stores the pre-calculated daily totals, so reports
-- read a few thousand summary rows instead.
--
-- Trade-off: the view is a SNAPSHOT. It must be refreshed (e.g. nightly)
-- to include new orders, and it uses extra storage.
-- =====================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_daily_sales;

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT o.order_date::date                AS sale_date,
       parent.name                       AS category,
       COUNT(DISTINCT o.order_id)        AS orders,
       SUM(oi.quantity)                  AS units_sold,
       SUM(oi.quantity * oi.unit_price)  AS revenue_ngn
FROM orders o
JOIN order_items      oi     ON oi.order_id   = o.order_id
JOIN product_variants v      ON v.variant_id  = oi.variant_id
JOIN products         p      ON p.product_id  = v.product_id
JOIN categories       child  ON child.category_id  = p.category_id
JOIN categories       parent ON parent.category_id = child.parent_category_id
WHERE o.order_status <> 'cancelled'
GROUP BY 1, 2;

-- A unique index is required for REFRESH ... CONCURRENTLY (see bottom)
CREATE UNIQUE INDEX uq_mv_daily_sales ON mv_daily_sales (sale_date, category);

ANALYZE mv_daily_sales;

-- NOTE: "orders" is counted per day PER CATEGORY. An order containing a phone
-- and a dress counts once in Electronics and once in Fashion, so do not add
-- this column up across categories. Revenue and units CAN be added up.

-- How much smaller is the summary than the raw data?
SELECT (SELECT COUNT(*) FROM order_items)    AS raw_order_item_rows,
       (SELECT COUNT(*) FROM mv_daily_sales) AS summary_rows;

\qecho '=================================================================='
\qecho 'Q6b  Monthly revenue since 1 Aug 2026 - from the materialised view'
\qecho '=================================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', sale_date)::date AS month,
       SUM(revenue_ngn)                     AS revenue_ngn
FROM mv_daily_sales
WHERE sale_date >= '2026-08-01'
GROUP BY 1
ORDER BY 1;

-- The actual report (for a screenshot)
SELECT date_trunc('month', sale_date)::date AS month,
       SUM(revenue_ngn)                     AS revenue_ngn
FROM mv_daily_sales
WHERE sale_date >= '2026-08-01'
GROUP BY 1
ORDER BY 1;

-- Bonus report the view makes cheap: revenue by category this year
SELECT category, SUM(units_sold) AS units, SUM(revenue_ngn) AS revenue_ngn
FROM mv_daily_sales
WHERE sale_date >= '2026-01-01'
GROUP BY category
ORDER BY revenue_ngn DESC;

-- Keeping it up to date. CONCURRENTLY lets reports keep reading the old
-- snapshot while the new one is built (no blocking), which is how a live
-- shop would run it, e.g. every night at 2am.
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
