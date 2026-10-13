# Advanced Database Systems Portfolio — MIT 8103

**Student:** Oluwaleimu Oluwasegun  
**Student ID:** 301865517  
**Programme:** Master of Information Technology, Miva Open University  
**Session:** 2026/2027 September Semester

---

## Case Study: ShopNaija Online Marketplace (simulated organisation)

### Nature of the business
ShopNaija is a simulated Nigerian online marketplace that sells electronics,
fashion, home goods and groceries to customers across Nigeria. Customers browse
products, place orders, pay online or on delivery, and track their packages
until delivery.

### Users of the database
- **Customers** — register, browse products, place orders, track deliveries
- **Store administrators** — add and update products, categories and prices
- **Inventory managers** — monitor and update stock levels
- **Finance staff** — confirm payments, process refunds, view sales reports
- **Delivery agents** — update shipment status from dispatch to delivery

### Major data stored
| Data | Examples |
|---|---|
| Customers | Name, email, phone, delivery addresses |
| Products | Name, category, price, SKU, product attributes (size, colour, storage) |
| Inventory | Stock quantity per product variant |
| Orders | Order date, status, items ordered, quantities, totals |
| Payments | Amount, method (card, transfer, pay-on-delivery), status |
| Deliveries | Shipment, delivery agent, tracking events, delivery status |

### Key database operations
1. Add and update products and their attributes
2. Place an order (create order, deduct stock, record payment)
3. Update stock levels and raise low-stock alerts
4. Process payments and reverse failed ones
5. Track deliveries from dispatch to doorstep
6. Produce sales and performance reports

---

## Portfolio Summary

| Folder | Portfolio | Key result |
|---|---|---|
| [`portfolio-1-database-design/`](portfolio-1-database-design/) | Database Design and Modelling | 12-table 3NF/BCNF schema; 100,000 simulated orders; 11 constraint tests all PASS |
| [`portfolio-2-query-optimisation/`](portfolio-2-query-optimisation/) | Query Processing and Optimisation | Parcel tracking 65.7 ms → 0.45 ms with a foreign-key index; monthly revenue 159 ms → 1.9 ms with a materialised view |
| [`portfolio-3-transactions-concurrency/`](portfolio-3-transactions-concurrency/) | Transactions and Concurrency | Lost update reproduced (1 phone sold twice) and fixed with pessimistic, optimistic and SERIALIZABLE control; deadlock demonstrated |
| [`portfolio-4-nosql/`](portfolio-4-nosql/) | NoSQL and Advanced Data Models | Same data as MongoDB documents + key-value cart; aggregation matches SQL to the naira; polyglot-persistence recommendation |
| [`portfolio-5-distributed-cloud/`](portfolio-5-distributed-cloud/) | Distributed and Cloud Databases | 3-node replica set: primary killed, new primary in 12.7 s, 45/45 orders saved; partition (CAP) test; hashed `customer_id` shard key |

Each folder has its own README explaining what was built, how it was tested, the results and the analysis,
with saved outputs in `results/` and screenshots in `evidence/`.

## How to Run

**Prerequisites:** PostgreSQL 18, MongoDB 8 with `mongosh` and MongoDB Compass, Docker Desktop, Git.

1. **Portfolios 1–3 (PostgreSQL):** create a database called `shopnaija`, then run the numbered `.sql` files in
   each folder in order (`01_…`, `02_…`). Portfolio 3's concurrency demos follow `03_concurrency_walkthrough.md`
   using two SQL Shell windows.
2. **Portfolio 4 (MongoDB):** in SQL Shell run `portfolio-4-nosql/01_export_from_postgres.sql` (creates the
   `data/` folder, which is not committed because it is ~150 MB), then run each script with
   `mongosh shopnaija --quiet --file <script>.js`.
3. **Portfolio 5 (Docker):** in `portfolio-5-distributed-cloud/` run `docker compose up -d`, then each script with
   `docker exec mongo1 mongosh --nodb --quiet --file /scripts/<script>.js` (see that README for the failover and
   partition steps). Needs the Portfolio 4 `data/` folder.

## Repository Structure

```
advanced-database-portfolio/
├── README.md                          ← this file: case study and overview
├── ai-use-log.md                      ← AI use declaration and dated log
├── REFLECTION.md                      ← individual technical reflection
├── evidence/                          ← Day 1 environment setup screenshots
├── portfolio-1-database-design/       ← schema, seed data, constraint tests, ERD, normalisation
├── portfolio-2-query-optimisation/    ← queries, indexes, materialised view, execution plans
├── portfolio-3-transactions-concurrency/  ← commit/rollback/savepoint, locking, isolation, deadlock
├── portfolio-4-nosql/                 ← PostgreSQL→MongoDB migration, CRUD, aggregation, key-value
└── portfolio-5-distributed-cloud/     ← Docker replica set, failover, partition, transactions, sharding
```

## Tools Used

PostgreSQL 18, pgAdmin 4, SQL Shell (psql), MongoDB 8, mongosh, MongoDB Compass, Docker Desktop,
dbdiagram.io, Git and GitHub, Visual Studio Code.

## Individual Technical Reflection

See [`REFLECTION.md`](REFLECTION.md): design choices, challenges faced and lessons learned.

## AI Use Declaration

AI assistance (Claude, Anthropic) was used for planning, drafting scripts and documentation, and troubleshooting.
Every script was run, and every output, timing and screenshot was produced, on my own computer.
Details and verification are recorded in [`ai-use-log.md`](ai-use-log.md).

## References

- The PostgreSQL Global Development Group. *PostgreSQL 18 Documentation*. https://www.postgresql.org/docs/18/
- MongoDB Inc. *MongoDB Manual*. https://www.mongodb.com/docs/manual/
- Docker Inc. *Docker Compose documentation*. https://docs.docker.com/compose/
- dbdiagram.io, used to draw the ER diagram. https://dbdiagram.io
- Federal Republic of Nigeria (2023). *Nigeria Data Protection Act, 2023*.
- All data is simulated, generated by `portfolio-1-database-design/02_seed_data.sql`; no real personal data was used.
