# Concurrency Walkthrough — Two Customers, One Phone

These demos need **two SQL Shell (psql) windows open at the same time**, each acting
as a different customer. You paste one line at a time, alternating between the
windows, in the order shown by the step numbers.

## Setting up the two windows

1. Open **SQL Shell (psql)** twice from the Start menu. Log in to `shopnaija` in both.
2. In the **first** window, type:
   ```
   \set PROMPT1 'A %/=# '
   ```
3. In the **second** window, type:
   ```
   \set PROMPT1 'B %/=# '
   ```
   The prompts now read `A shopnaija=#` and `B shopnaija=#`, so screenshots show which
   customer did what.
4. Snap the windows side by side: click window A and press **Windows + ←**, then click
   window B and press **Windows + →**.

**Before every demo**, reset the flash sale in either window:
```sql
SELECT reset_flash_sale();
```

**After every demo**, check the result in either window:
```sql
SELECT * FROM flash_sale_status;
```

---

## Demo 3 — The problem: lost update (overselling)

**Scenario:** the app reads the stock, checks it is above zero, calculates the new value
(1 − 1 = 0) and writes it back. Both customers do this at almost the same time, using
PostgreSQL's default isolation level, **READ COMMITTED**, with no locking.

| Step | Window A (customer 1) | Window B (customer 2) | What you should see |
|---|---|---|---|
| 1 | `BEGIN;` | | |
| 2 | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id();` | | A sees **1** |
| 3 | | `BEGIN;` | |
| 4 | | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id();` | B also sees **1** |
| 5 | `UPDATE inventory SET quantity_on_hand = 0 WHERE variant_id = flash_id();` | | |
| 6 | `SELECT record_flash_order(1);` | | an order number |
| 7 | `COMMIT;` | | |
| 8 | | `UPDATE inventory SET quantity_on_hand = 0 WHERE variant_id = flash_id();` | `UPDATE 1` (it worked!) |
| 9 | | `SELECT record_flash_order(2);` | another order number |
| 10 | | `COMMIT;` | |
| 11 | `SELECT * FROM flash_sale_status;` | | stock 0, **phones_sold 2, OVERSOLD!** |

📸 `evidence/p3-demo3-lost-update.png` — both windows after step 11.

**Why:** both customers based their decision on a value that was already out of date.
B's write simply overwrote A's: one phone, two paid orders, one angry customer.

---

## Demo 4 — Fix 1: pessimistic locking (`SELECT ... FOR UPDATE`)

**Idea:** lock the stock row *when reading it*, so nobody else can read-to-buy until you
have finished.

| Step | Window A | Window B | What you should see |
|---|---|---|---|
| 0 | `SELECT reset_flash_sale();` | | |
| 1 | `BEGIN;` | | |
| 2 | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id() FOR UPDATE;` | | A sees **1** and holds the lock |
| 3 | | `BEGIN;` | |
| 4 | | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id() FOR UPDATE;` | **B freezes**: it is waiting for A |
| 5 | `SELECT pid, wait_event_type, state, left(query, 60) FROM pg_stat_activity WHERE datname = 'shopnaija' AND wait_event_type = 'Lock';` | (still waiting) | A sees B's session listed as waiting on a **Lock** |
| 6 | `UPDATE inventory SET quantity_on_hand = 0 WHERE variant_id = flash_id();` | | |
| 7 | `SELECT record_flash_order(1);` | | |
| 8 | `COMMIT;` | | **B un-freezes instantly** and shows **0** |
| 9 | | `ROLLBACK;` | B sees 0 → sold out → gives up |
| 10 | `SELECT * FROM flash_sale_status;` | | stock 0, phones_sold 1, **OK** |

📸 `evidence/p3-demo4-for-update-waiting.png` — after step 5 (B frozen, A shows the lock).
📸 `evidence/p3-demo4-for-update-result.png` — after step 10.

---

## Demo 5 — Fix 2: optimistic locking (version number)

**Idea:** don't lock anything while reading. When writing, only succeed **if nobody has
changed the row since you read it**, checked using a `version` number.

| Step | Window A | Window B | What you should see |
|---|---|---|---|
| 0 | `SELECT reset_flash_sale();` | | |
| 1 | `SELECT quantity_on_hand, version FROM inventory WHERE variant_id = flash_id();` | | stock 1, version **1** |
| 2 | | `SELECT quantity_on_hand, version FROM inventory WHERE variant_id = flash_id();` | stock 1, version **1** |
| 3 | `BEGIN;` | | |
| 4 | `UPDATE inventory SET quantity_on_hand = 0, version = version + 1 WHERE variant_id = flash_id() AND version = 1;` | | `UPDATE 1` |
| 5 | `SELECT record_flash_order(1);` | | |
| 6 | `COMMIT;` | | |
| 7 | | `UPDATE inventory SET quantity_on_hand = 0, version = version + 1 WHERE variant_id = flash_id() AND version = 1;` | **`UPDATE 0`**: nothing changed |
| 8 | | `SELECT quantity_on_hand, version FROM inventory WHERE variant_id = flash_id();` | stock 0, version 2 → sold out, B does not create an order |
| 9 | `SELECT * FROM flash_sale_status;` | | stock 0, phones_sold 1, **OK** |

📸 `evidence/p3-demo5-optimistic.png` — after step 9 (B's `UPDATE 0` visible).

**Why `UPDATE 0` matters:** B's update said "only if version is still 1". A had already
made it 2, so zero rows matched. The application checks the row count; 0 means "someone
beat you to it, re-read and try again".

---

## Demo 6 — Fix 3: SERIALIZABLE isolation

**Idea:** let the database detect the conflict itself and refuse the second transaction.

| Step | Window A | Window B | What you should see |
|---|---|---|---|
| 0 | `SELECT reset_flash_sale();` | | |
| 1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | | |
| 2 | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id();` | | **1** |
| 3 | | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| 4 | | `SELECT quantity_on_hand FROM inventory WHERE variant_id = flash_id();` | **1** |
| 5 | `UPDATE inventory SET quantity_on_hand = 0 WHERE variant_id = flash_id();` | | |
| 6 | `SELECT record_flash_order(1);` | | |
| 7 | `COMMIT;` | | |
| 8 | | `UPDATE inventory SET quantity_on_hand = 0 WHERE variant_id = flash_id();` | **ERROR: could not serialize access due to concurrent update** |
| 9 | | `ROLLBACK;` | |
| 10 | `SELECT * FROM flash_sale_status;` | | stock 0, phones_sold 1, **OK** |

📸 `evidence/p3-demo6-serializable.png` — after step 10.

**Note:** this is the same SQL as Demo 3; only the isolation level changed. In a real app,
B's code would catch this error and retry the whole purchase, then see stock 0.

---

## Demo 7 — Isolation anomaly: non-repeatable read

**Scenario:** during checkout, the app reads a product's price at the start and again
when building the receipt. Meanwhile an admin changes the price.

**Part 1: READ COMMITTED (the default)**

| Step | Window A (checkout) | Window B (admin) | What you should see |
|---|---|---|---|
| 1 | `BEGIN;` | | |
| 2 | `SELECT price FROM product_variants WHERE sku = 'SKU-5-1';` | | e.g. **118400.00** |
| 3 | | `UPDATE product_variants SET price = price + 1000 WHERE sku = 'SKU-5-1';` | `UPDATE 1` (saved immediately) |
| 4 | `SELECT price FROM product_variants WHERE sku = 'SKU-5-1';` | | **119400.00**: changed mid-transaction! |
| 5 | `COMMIT;` | | |

📸 `evidence/p3-demo7-read-committed.png`

**Part 2: REPEATABLE READ**

| Step | Window A (checkout) | Window B (admin) | What you should see |
|---|---|---|---|
| 6 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | | |
| 7 | `SELECT price FROM product_variants WHERE sku = 'SKU-5-1';` | | **119400.00** |
| 8 | | `UPDATE product_variants SET price = price - 1000 WHERE sku = 'SKU-5-1';` | `UPDATE 1` (price restored) |
| 9 | `SELECT price FROM product_variants WHERE sku = 'SKU-5-1';` | | still **119400.00**: A keeps its snapshot |
| 10 | `COMMIT;` | | |
| 11 | `SELECT price FROM product_variants WHERE sku = 'SKU-5-1';` | | now **118400.00** (new transaction, new snapshot) |

📸 `evidence/p3-demo7-repeatable-read.png`

---

## Demo 8 — Deadlock

**Scenario:** two staff members restock two products each, but update them in
**opposite orders**.

| Step | Window A | Window B | What you should see |
|---|---|---|---|
| 1 | `BEGIN;` | | |
| 2 | `UPDATE inventory SET quantity_on_hand = quantity_on_hand + 5 WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-6-1');` | | A locks product 6 |
| 3 | | `BEGIN;` | |
| 4 | | `UPDATE inventory SET quantity_on_hand = quantity_on_hand + 5 WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-7-1');` | B locks product 7 |
| 5 | `UPDATE inventory SET quantity_on_hand = quantity_on_hand + 5 WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-7-1');` | | **A freezes**: waiting for B |
| 6 | | `UPDATE inventory SET quantity_on_hand = quantity_on_hand + 5 WHERE variant_id = (SELECT variant_id FROM product_variants WHERE sku = 'SKU-6-1');` | after ~1 second: **ERROR: deadlock detected** in one window; the other un-freezes |
| 7 | `ROLLBACK;` | `ROLLBACK;` | both clean up (stock unchanged) |

📸 `evidence/p3-demo8-deadlock.png` — after step 6.

**Why:** A waits for B, and B waits for A, forever. PostgreSQL checks for this after 1
second (`deadlock_timeout`), picks one transaction as the victim and cancels it so the
other can finish. **Prevention:** always update rows in the same order (for example, by
ascending `variant_id`), so a cycle can never form.
