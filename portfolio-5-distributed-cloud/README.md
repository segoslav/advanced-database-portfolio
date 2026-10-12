# Portfolio 5 — Distributed and Cloud Databases

**Case study:** ShopNaija Online Marketplace
**Setup:** a 3-member MongoDB replica set in Docker, loaded with the Portfolio 4 ShopNaija documents

## Aim

Show how ShopNaija's database keeps working when a server fails, what "consistent"
means once data lives on several servers, and how the shop would grow beyond one
machine (sharding) and be deployed in the cloud.

## Architecture

```mermaid
flowchart LR
    APP["ShopNaija app<br/>(mongosh scripts)"] -- "writes + reads" --> P
    subgraph RS["Replica set rs0 (Docker network: shopnaija-net)"]
        P["mongo1<br/>PRIMARY<br/>priority 2<br/>port 27021"]
        S1["mongo2<br/>SECONDARY<br/>port 27022"]
        S2["mongo3<br/>SECONDARY<br/>port 27023"]
        P -- "oplog replication" --> S1
        P -- "oplog replication" --> S2
        S1 <-. "heartbeats every 2 s" .-> S2
        P <-. "heartbeats" .-> S1
        P <-. "heartbeats" .-> S2
    end
```

All writes go to the **primary**. Each secondary continuously copies the primary's
operation log (**oplog**) and replays it, so all three hold the same data. Members
check on each other every 2 seconds; if the primary disappears for 10 seconds, the
remaining members **elect** a new one, provided a majority (2 of 3) can still see each other.

## Contents of this folder

| File | What it does |
|---|---|
| `docker-compose.yml` | Defines the three MongoDB servers, their network and storage |
| `scripts/common.js` | Shared helpers (connection strings, status printing) |
| `scripts/00_status.js` | Shows every member's role and health; works even when one is down |
| `scripts/01_init_replica_set.js` | Creates replica set `rs0` and waits for the first election |
| `scripts/02_load_shopnaija.js` | Loads products, customers and orders; checks each member has a full copy |
| `scripts/03_replication_check.js` | Follows one write from the primary to each secondary, via the oplog |
| `scripts/04_failover_writer.js` | Places an order every second while the primary is killed |
| `scripts/05_write_concern.js` | Times `w:1`, `w:majority` and `w:3`; compares read concerns |
| `scripts/06a_partition_write.js` / `06b_read_on_mongo3.js` | Network partition: writes on the majority side, stale reads on the cut-off side |
| `scripts/07_transaction.js` | Multi-document transaction: stock + order commit or abort together |
| `scripts/08_shard_key_analysis.js` | Measures three candidate shard keys against the real order data |
| `results/` | Saved output of every script |
| `evidence/` | Screenshots (Docker Desktop, failover, partition) |

## Results

**Replication** (`results/02_load_output.txt`, `results/03_replication_output.txt`)

| Member | Role | Products / customers / orders held | Test write found after | Lag behind primary |
|---|---|---|---|---|
| mongo1 | PRIMARY | 2,001 / 5,000 / 100,002 | 0 ms (written here) | 0 s |
| mongo2 | SECONDARY | 2,001 / 5,000 / 100,002 | ~20 ms | ≤ 1 s |
| mongo3 | SECONDARY | 2,001 / 5,000 / 100,002 | ~0 ms | ≤ 1 s |

Loading 107,003 documents with `w: "majority"` took 39.7 seconds. All three members ended with
identical counts. (Lag is reported in whole seconds, so "1 s" means "under a second".)

**Failover**: primary killed with `docker kill mongo1` (`results/04_failover_output.txt`)

| Measure | Value |
|---|---|
| Primary killed | between order #15 (14:16:42) and order #16 |
| Longest single write during the election | **12,690 ms** (order #16), against a normal 12–50 ms |
| New primary | mongo2 |
| Orders attempted / stored / lost | 45 / 45 / **0** |
| Status during the outage | mongo1 health 0 (unreachable); mongo2 PRIMARY; mongo3 SECONDARY |
| After `docker start mongo1` | Rejoined, caught up, and **took back the primary role** (priority 2) |

**Write concern** (`results/05_write_concern_output.txt`): 300 inserts each

| Write concern | Total ms | Avg ms per write | Confirmed when… | Survives losing |
|---|---|---|---|---|
| `w: 1` | 1,133 | 3.78 | the primary has it in memory | nothing (primary only) |
| `w: "majority"` | 4,398 | 14.66 | 2 of 3 servers have it **saved to disk (journaled)** | any 1 server, even a power cut |
| `w: 3` | 1,439 | 4.80 | all 3 servers have it in memory | any 1 server, but **fails** if any server is down |

**Network partition**: mongo3 cut off (`results/06_partition_output.txt`)

| Check | During partition (14:33) | After reconnecting (14:37) |
|---|---|---|
| mongo3 as seen by the primary | not reachable, health 0 | SECONDARY, health 1 |
| Other members as seen by mongo3 | both not reachable | mongo1 PRIMARY, mongo2 SECONDARY |
| ORDER-A (`w: majority`) | **Saved**, confirmed by mongo1 + mongo2 | — |
| ORDER-B (`w: 3`) | **Not confirmed** after 5,029 ms (`WriteConcernFailed`), but stored on the primary | — |
| ORDER-A visible on mongo3 | NOT FOUND (stale) | FOUND |
| ORDER-B visible on mongo3 | NOT FOUND (stale) | FOUND |

**Transaction** (`results/07_transaction_output.txt`)

| Customer | Stock before | Outcome | Order visible to others before commit? | Stock after |
|---|---|---|---|---|
| 1 | 1 | **COMMITTED**: stock reduced and order created together | NO (YES only after commit) | 0 |
| 2 | 0 | **ABORTED** (out of stock): nothing saved | — | 0 |

Flash-sale orders stored: 1. Stock left: 0. No overselling, and no half-finished order.

## Analysis

**Replication.** Every order written to the primary appeared on both secondaries within
milliseconds. Secondaries do not receive the data directly from the application: they copy
the primary's oplog, a running list of every change, and replay it in order. All three
members therefore hold full, identical copies: the 100,000+ orders exist three times.

**Availability and failover.** Killing the primary simulates a server crash. For about
12.7 seconds no primary existed: members wait 10 s (`electionTimeoutMillis`) before deciding the
primary is gone, then hold an election, which mongo2 won. During that time one order (#16) paused. The driver then found the new
primary and **retried the write automatically** (`retryWrites`), so no order was lost. When
mongo1 came back it first rejoined as a secondary and copied the writes it had missed; because
it has the highest priority it then took the primary role back. Without replication, the crash
would have taken the shop offline until someone repaired the server.

**Consistency: write and read concern.** Write concern is a dial between speed and safety.
`w: 1` was fastest (3.8 ms per write), but an order confirmed only by the primary can be lost if
the primary dies before copying it. The surprise was that `w: "majority"` (14.7 ms) was **slower
than `w: 3`** (4.8 ms), even though it waits for fewer servers. The reason is *what* it waits for:
by default MongoDB only confirms a majority write once each of those servers has written it to
its on-disk **journal**, while `w: 3` (with no `j` option) only waits until all three have it in
memory. So `w: "majority"` is the stronger durability guarantee: the order survives even a
simultaneous power cut, and majority-committed data can never be rolled back. `w: 3` looks
safest on paper but makes the shop **unavailable for writes whenever any one server is down**,
as the partition test showed (ORDER-B timed out after 5 seconds).
**ShopNaija should use `w: "majority"` for orders and payments**, and `readConcern: "majority"`
for anything financial, so reports never show data that could later disappear.

**The CAP theorem in practice.** During a network partition a distributed database must choose
between **C**onsistency and **A**vailability. The partition test shows MongoDB's choice:

- The **majority side** (mongo1 + mongo2) kept accepting writes: it stayed *consistent and available*.
- The **cut-off minority** (mongo3) refused writes, because a server that cannot reach a majority
  must not become primary, or two primaries could accept conflicting orders. That preserves
  consistency at the cost of availability on that side.
- mongo3 still **answered reads, but with stale data**: ORDER-A and ORDER-B were missing until the
  network was restored. Reads from secondaries are therefore only *eventually consistent*.

For ShopNaija: stock levels, payments and order placement must always read from the **primary**,
with majority concern. Product browsing, reviews and order-history pages can safely read from
secondaries, which spreads the load and tolerates being a second or two behind.

**Transactions.** Portfolio 4 could make a single document change atomic but not "reduce stock
AND create the order" together. On the replica set, a multi-document transaction did exactly
that: customer 1's stock change and order committed together, and the order was invisible to
everyone else until commit (isolation). Customer 2's transaction found no stock, aborted, and
left nothing behind. This is the MongoDB equivalent of Portfolio 3's `BEGIN … COMMIT / ROLLBACK`.

## Sharding design

Replication copies **all** data to every server. It improves availability and read capacity,
but every server still stores everything and all writes still go through one primary. When
ShopNaija outgrows one machine, **sharding** splits the `orders` collection across several
replica sets (shards), each holding part of the data, with a router (`mongos`) directing each
query to the right shard.

```mermaid
flowchart TB
    APP[ShopNaija app] --> R["mongos router"]
    R --> CFG[("config servers<br/>(which data is where)")]
    R --> SH1["Shard 1<br/>replica set"]
    R --> SH2["Shard 2<br/>replica set"]
    R --> SH3["Shard 3<br/>replica set"]
```

The key decision is the **shard key**. `08_shard_key_analysis.js` measured three options on the
real order data (`results/08_shard_key_output.txt`):

| Shard key | Data spread | Write spread | "Show my orders" query | Verdict |
|---|---|---|---|---|
| `shipping_address.state` | Uneven: Lagos holds 16.2% of orders, **2.9× an average state**; only 18 key values | Uneven | All shards | ✗ Hot shard for Lagos; can never split into more than 18 pieces |
| `order_date` (ranged) | Even over time (~5,400–5,500 orders per month) | **All new orders hit one shard** | All shards | ✗ Ever-increasing key, hot shard |
| `customer_id` (hashed) | **33.2% / 33.6% / 33.1%** across 3 shards | Even | **One shard** | ✓ Recommended |

**Recommendation:** shard `orders` on `{ customer_id: "hashed" }`. Orders spread evenly, new
orders spread evenly, and the most frequent customer query ("my orders") is answered by a single
shard. The cost is that company-wide reports (revenue by month) must query every shard and
combine the results, which is acceptable for back-office reporting. `products` (2,000 documents)
and `customers` are small enough not to need sharding.

## Cloud deployment design

| Concern | Design for ShopNaija |
|---|---|
| Service | **MongoDB Atlas** (managed MongoDB) for the document data; a managed PostgreSQL service (e.g. AWS RDS) for payments and stock (Portfolio 4 recommendation) |
| Region | The nearest cloud regions to Nigeria are in South Africa (e.g. AWS `af-south-1` Cape Town, Azure South Africa North) and Western Europe; the choice balances latency to Nigerian customers against cost and service availability |
| Availability | 3-member replica set spread across **3 availability zones** (separate data centres), so a whole data centre can fail, exactly as mongo1 failed in this test |
| Scaling | Start with one replica set; move to the hashed `customer_id` sharding design when data or write volume outgrows one primary |
| Backups | Continuous cloud backup with point-in-time restore, so the database can be rewound to just before a mistake |
| Security | Private network access only, TLS encryption in transit, encryption at rest, separate database users per application role |
| Compliance | Customer personal data must be handled in line with the **Nigeria Data Protection Act 2023**; storing data outside Nigeria needs the safeguards the Act requires |
| Cost control | Right-size the instance tier; read-heavy pages use secondaries before paying for bigger servers |

This local Docker cluster mirrors that production design on a small scale: three replica-set
members, majority write concern, automatic failover and retryable writes.

## Evidence

| File | Shows |
|---|---|
| `evidence/p5-docker-containers.png` | Docker Desktop with mongo1, mongo2 and mongo3 running |
| `evidence/p5-replica-set-status.png` | One PRIMARY and two SECONDARY members |
| `evidence/p5-failover.png` | Order writes continuing through the kill of the primary |
| `evidence/p5-status-after-failover.png` | New primary elected; mongo1 unreachable |
| `evidence/p5-partition-mongo3.png` | mongo3 cut off: orders NOT FOUND |
| `evidence/p5-partition-healed.png` | After reconnecting: orders FOUND |
| `evidence/p5-transaction.png` | Commit for customer 1, abort for customer 2 |
