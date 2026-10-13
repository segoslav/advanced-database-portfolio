# Portfolio 3 — Transactions and Concurrency

**Case study:** ShopNaija Online Marketplace
**Database:** PostgreSQL (Portfolio 1 schema and data)

## Aim

Show how ShopNaija keeps orders, stock and payments correct when things fail
part-way through, and when many customers buy at the same time, using a realistic
problem: **a flash sale with one phone left and two customers trying to buy it**.

## Contents of this folder

| File | What it is |
|---|---|
| `00_setup.sql` | Creates the one-unit flash-sale phone, a `version` column for optimistic locking, and helper functions |
| `01_commit_transaction.sql` | Demo 1: a complete "place order" transaction across four tables, ending in `COMMIT` |
| `02_rollback_and_savepoint.sql` | Demo 2: explicit `ROLLBACK`, automatic abort on a constraint violation, and `SAVEPOINT` |
| `03_concurrency_walkthrough.md` | Demos 3–8: two-window concurrency experiments, step by step |
| `results/` | Saved output of Demos 1 and 2 |
| `evidence/` | Side-by-side screenshots of the two-window demos |

## ACID in the ShopNaija checkout

| Property | Where it is demonstrated |
|---|---|
| **Atomicity**: all steps or none | Demo 1 commits order + items + stock + payment together; Demo 2A/2B roll back all of them |
| **Consistency**: rules always hold | Demo 2B: the `chk_stock_not_negative` constraint refuses to let stock go below zero and aborts the transaction |
| **Isolation**: concurrent users don't corrupt each other | Demos 3–7: lost update, three fixes, and read anomalies under different isolation levels |
| **Durability**: committed data survives | After `COMMIT` in Demo 1 the order is visible from any new session, even after restarting SQL Shell |

## Summary of results

| Demo | Technique | Outcome |
|---|---|---|
| 1 | `BEGIN … COMMIT` | Order, item, stock reduction and payment saved together |
| 2A | Explicit `ROLLBACK` (card declined) | Order discarded; stock restored to its original value |
| 2B | Automatic abort (CHECK constraint) | Ordering 1,000 units of an item with 77 in stock failed; all later commands refused until `ROLLBACK` |
| 2C | `SAVEPOINT` + `ROLLBACK TO SAVEPOINT` | Failed payment attempt undone; order kept; retry by bank transfer committed |
| 3 | No locking, READ COMMITTED | **Oversold**: 1 phone, 2 paid orders (lost update) |
| 4 | Pessimistic locking (`FOR UPDATE`) | Second customer waited, then saw 0 stock. 1 sale |
| 5 | Optimistic locking (`version` column) | Second update matched 0 rows → retry → sold out. 1 sale |
| 6 | `SERIALIZABLE` isolation | Second transaction refused with a serialization error. 1 sale |
| 7 | READ COMMITTED vs REPEATABLE READ | Price changed mid-transaction under READ COMMITTED; stayed fixed under REPEATABLE READ |
| 8 | Opposite lock order | Deadlock detected after ~1 s; one transaction cancelled |

## Analysis

**Why the lost update happened (Demo 3).** Under READ COMMITTED each statement sees the
latest committed data, but nothing stops two transactions from *reading* the same row at
the same time. Both customers saw "1 in stock", and each wrote back a value calculated from
that stale read. The database did exactly what it was told; the bug is the read–decide–write
pattern without protection. (If the app had written `quantity_on_hand = quantity_on_hand - 1`
instead of a pre-calculated `0`, the second update would have produced −1 and been
rejected by the CHECK constraint, which is a useful second line of defence, as Demo 2B shows.)

**Comparing the three fixes**

| | Pessimistic (`FOR UPDATE`) | Optimistic (`version`) | `SERIALIZABLE` |
|---|---|---|---|
| How it works | Lock the row when reading; others wait | No lock; write only if version unchanged | Database detects conflicting transactions and cancels one |
| Who handles the conflict | Database (makes others wait) | Application (checks row count, retries) | Application (catches error, retries) |
| Cost | Waiting; risk of deadlock if lock order differs | Retries when conflicts are frequent | Retries; some extra tracking overhead |
| Best fit at ShopNaija | **Checkout / stock reduction**: high contention on popular items during flash sales | Admin editing product details: conflicts are rare | Complex multi-step operations such as end-of-day stock reconciliation |

**Recommendation:** ShopNaija should use `SELECT … FOR UPDATE` when reducing stock at checkout,
because during a flash sale conflicts are *expected*, and making customers wait a few
milliseconds is better than failing and retrying. It should keep the CHECK constraint as a
safety net, and lock items in ascending `variant_id` order to avoid deadlocks (Demo 8).

**Isolation levels (Demo 7).** READ COMMITTED gives each *statement* a fresh view of the
data, so a price can change between two reads in the same checkout, a *non-repeatable
read*. REPEATABLE READ gives the whole *transaction* one snapshot taken at its first query,
so the price stays consistent from basket to receipt. PostgreSQL implements this with
MVCC (multi-version concurrency control): the admin's update creates a new version of the
row while the checkout keeps reading the old one, so neither has to wait for the other.

**Sequences are not rolled back (Demo 2).** The order numbers used by the rolled-back
transactions in 2A and 2B were skipped, not reused. Sequences deliberately ignore rollbacks
so that concurrent transactions never wait for each other just to get an ID. Gaps in order
numbers are therefore normal and not a sign of lost data.

## Evidence

| File | Shows |
|---|---|
| `results/demo1_commit.txt` | Full output of Demo 1 |
| `results/demo2_rollback_savepoint.txt` | Full output of Demo 2 (query results) |
| `evidence/p3-demo2-expected-errors.png` | The three expected errors from Demo 2B and 2C |
| `evidence/p3-demo3-lost-update.png` | Overselling: 2 orders for 1 phone |
| `evidence/p3-demo4-for-update-waiting.png` | Window B blocked; `pg_stat_activity` showing the lock wait |
| `evidence/p3-demo4-for-update-result.png` | One sale only |
| `evidence/p3-demo5-optimistic.png` | `UPDATE 0` in window B |
| `evidence/p3-demo6-serializable.png` | Serialization error in window B |
| `evidence/p3-demo7-read-committed.png` | Price changing inside one transaction |
| `evidence/p3-demo8-deadlock.png` | Deadlock detected |
