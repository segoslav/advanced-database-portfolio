# Portfolio 2 — Query Processing and Optimisation

**Case study:** ShopNaija Online Marketplace
**Database:** PostgreSQL, using the Portfolio 1 schema and data
(100,000 orders, ~250,000 order items, ~264,000 delivery events)

## Aim

Take eight everyday ShopNaija queries, measure how PostgreSQL executes them,
add targeted optimisations, and measure again, explaining *why* each change
helped (or did not).

## Contents of this folder

| File | What it is |
|---|---|
| `01_business_queries.sql` | 8 business queries, each wrapped in `EXPLAIN (ANALYZE, BUFFERS)` |
| `02_create_indexes.sql` | 7 targeted indexes, one per query, with the reason for each |
| `03_materialized_view.sql` | Materialised view for sales reporting (fixes Q6) |
| `04_drop_indexes.sql` | Reset script to repeat the "before" measurements |
| `results/before_plans.txt` | Full execution plans **before** optimisation |
| `results/after_plans.txt` | Full execution plans **after** indexes |
| `results/materialized_view.txt` | Plan and output of the materialised view |
| `evidence/` | pgAdmin screenshots, including graphical plans |

## Method

1. Run `01_business_queries.sql` once to warm the cache, then again with output
   saved to `results/before_plans.txt`. (The first run reads data from disk, so it is
   slower and unfair to compare.)
2. Run `02_create_indexes.sql`.
3. Repeat step 1, saving to `results/after_plans.txt`.
4. Run `03_materialized_view.sql`, saving to `results/materialized_view.txt`.

Execution times vary slightly between runs and computers; the **plan changes**
(which scan type is used) are what matter most.

## Results

| # | Business query | Before: plan | After: plan | Before (ms) | After (ms) | Optimisation used |
|---|---|---|---|---|---|---|
| Q1 | Customer order history | Seq Scan on orders (100k rows) | Bitmap Index Scan | 5.008|0.878 | Composite index `(customer_id, order_date DESC)` |
| Q2 | Track a delivery | Parallel Seq Scan on delivery_events (264k rows) | Index Scan | 65.702|0.446 | Index on foreign key `delivery_events(shipment_id, event_time)` |
| Q3 | Sales history of one variant | Parallel Seq Scan on order_items (250k rows) | Bitmap Index Scan |28.049 |0.825  | Index on `order_items(variant_id)` |
| Q4 | Fulfilment queue | Seq Scan on orders | Bitmap Index Scan on partial index |21.800 | 2.368| Partial index `WHERE order_status IN (...)` |
| Q5 | Case-insensitive email lookup | Seq Scan on customers | Index Scan |4.794 |0.053 | Expression index on `lower(email)` |
| Q6 | Monthly revenue | Seq Scan on orders + order_items, Hash Join | Index on orders, but still Seq Scan on order_items |159.183 |103.252 | Index on `order_date` — **little gain** (see analysis) |
| Q6b | Monthly revenue (via view) | — | Bitmap Index Scan on 2,785 summary rows | — | 1.898| Materialised view `mv_daily_sales` |
| Q7 | Search by attributes (JSONB) | Seq Scan on product_variants | Bitmap Index Scan (GIN) |1.860 | 1.599| GIN index `jsonb_path_ops` |
| Q8 | Low-stock alert | Seq Scan on inventory | Seq Scan (unchanged) | 1.867| 1.800| **None — deliberately** |

Times are the `Execution Time` values from `results/before_plans.txt` and `results/after_plans.txt`
(Q6b from `results/materialized_view.txt`).

## Analysis

**Q1 – Composite index.** Without an index, PostgreSQL read all 100,000 orders to find
the 29 belonging to customer 2955, then sorted them. The composite index stores orders
grouped by customer and already ordered by date, so it jumps straight to the 29 rows.
Column order matters: `(customer_id, order_date)` serves "this customer's orders";
`(order_date, customer_id)` would not.

**Q2 – Foreign keys are not automatically indexed.** Finding the shipment by tracking
number was already fast (the `UNIQUE` constraint created an index in Portfolio 1). The
slow part was finding its 3 tracking events among ~264,000 rows. PostgreSQL indexes
primary keys and unique columns, but **not** foreign keys, so every "track my parcel"
request scanned the whole table. This is the most important fix for customers, because
tracking is one of the most frequent operations on an e-commerce site.

**Q3 – Leading column of a composite key.** `order_items` already has a primary key
index on `(order_id, variant_id)`, but it cannot help a search by `variant_id` alone, for
the same reason a phone book sorted by surname cannot find everyone called "Emeka" quickly.
A separate index on `variant_id` fixed this.

**Q4 – Partial index.** Only ~1,400 of 100,000 orders (1.4%) are still open. A partial index
stores only those rows, so it is 48 kB instead of ~2 MB for a full index, and delivered
orders never touch it. Ideal for a "work queue" that staff check constantly.

**Q5 – Expression index.** The `UNIQUE` index on `email` stores emails exactly as typed. A
search on `lower(email)` is a different expression, so the planner ignored it and scanned
the table. Indexing the expression itself makes case-insensitive login and support lookups
instant.

**Q6 – When an index is not enough.** The date index correctly found the ~11,000 recent
orders, but the query still had to join them to `order_items`, and the planner chose to
read all 250,000 item rows into a hash table, which is the cheapest way to join that many rows.
The bottleneck was the volume of data, not finding it. The fix was a **materialised view**
that pre-calculates daily revenue per category (2,785 rows instead of 250,228). Revenue
figures match the original query exactly. The trade-off is freshness: the view is a
snapshot and must be refreshed (e.g. nightly with `REFRESH MATERIALIZED VIEW CONCURRENTLY`,
which does not block readers).

**Q7 – GIN index for JSONB.** Normal (B-tree) indexes cannot search *inside* a JSON
document. A GIN index records each key/value pair, so "contains `storage_gb: 256` and
`ram_gb: 16`" becomes an index lookup. `jsonb_path_ops` was chosen because it is smaller and
faster for `@>` (contains) searches, which is the only operator this shop needs. The
product table is small today, so the absolute saving is small, but this query is
run on every product filter click, and the catalogue will grow.

**Q8 – Deliberately not indexed.** The inventory table has only ~5,000 rows (about 30 data
pages). Reading it whole takes around 1 ms, faster than using an index. The plan also shows
an interesting estimation error: the planner expected ~1,650 rows but found ~244. PostgreSQL
cannot estimate comparisons *between two columns* (`quantity_on_hand <= reorder_level`), so
it uses a default guess of one-third. At this size it makes no difference, but it shows
why `EXPLAIN ANALYZE` (estimated vs actual rows) is worth reading carefully.

## Cost of the optimisations

Indexes are not free. Together they use about **15 MB** of extra storage (listed at the end
of `02_create_indexes.sql`), and every `INSERT` into `orders` now updates three extra
indexes. For ShopNaija this is a good trade, as the shop reads far more than it writes (many
product searches and tracking checks per order placed), but it is why indexes were added only
where a measured query needed them, and why Q8 was left alone.

## Evidence

| Screenshot | Shows |
|---|---|
| `evidence/p2-q2-before-graphical.png` | pgAdmin graphical plan for Q2 before indexing |
| `evidence/p2-q2-after-graphical.png` | Same query after indexing |
| `evidence/p2-indexes-created.png` | Index list and sizes from `02_create_indexes.sql` |
| `evidence/p2-materialized-view.png` | Monthly revenue report from the view |
