# Portfolio 1 — Database Design and Modelling

**Case study:** ShopNaija Online Marketplace (simulated e-commerce platform)
**Database:** PostgreSQL

## Contents of this folder

| File | What it is |
|---|---|
| `01_schema.sql` | Creates the 12 tables with primary keys, foreign keys and constraints |
| `02_seed_data.sql` | Generates realistic simulated data (5,000 customers, 100,000 orders, ~250,000 order items) |
| `03_constraint_tests.sql` | Tries to insert 11 kinds of bad data and proves each is rejected |
| `erd.dbml` | Source of the ER diagram (for dbdiagram.io) |
| `erd.png` | Exported ER diagram |
| `normalisation.md` | Step-by-step normalisation from UNF to 3NF/BCNF, plus design decisions |
| `evidence/` | Screenshots of the scripts running |

## How to run

1. In pgAdmin, create a database called `shopnaija`.
2. Open the Query Tool on `shopnaija` and run, in order:
   `01_schema.sql` → `02_seed_data.sql` → `03_constraint_tests.sql`.
3. `02_seed_data.sql` ends by printing row counts; `03_constraint_tests.sql` prints
   11 `PASS` messages in the Messages tab.

## ER Diagram

![ER diagram](erd.png)

The same diagram in Mermaid (GitHub renders it automatically):

```mermaid
erDiagram
    CUSTOMERS ||--o{ ADDRESSES : "has"
    CUSTOMERS ||--o{ ORDERS : "places"
    ADDRESSES ||--o{ ORDERS : "ships to"
    CATEGORIES ||--o{ CATEGORIES : "parent of"
    CATEGORIES ||--o{ PRODUCTS : "groups"
    PRODUCTS ||--|{ PRODUCT_VARIANTS : "comes in"
    PRODUCT_VARIANTS ||--|| INVENTORY : "stocked as"
    ORDERS ||--|{ ORDER_ITEMS : "contains"
    PRODUCT_VARIANTS ||--o{ ORDER_ITEMS : "sold as"
    ORDERS ||--o{ PAYMENTS : "paid by"
    ORDERS ||--o| SHIPMENTS : "shipped as"
    DELIVERY_AGENTS ||--o{ SHIPMENTS : "delivers"
    SHIPMENTS ||--o{ DELIVERY_EVENTS : "tracked by"

    CUSTOMERS {
        int customer_id PK
        varchar email UK
        varchar phone UK
        varchar first_name
        varchar last_name
    }
    ADDRESSES {
        int address_id PK
        int customer_id FK
        varchar city
        varchar state
        boolean is_default
    }
    CATEGORIES {
        int category_id PK
        varchar name UK
        int parent_category_id FK
    }
    PRODUCTS {
        int product_id PK
        int category_id FK
        varchar name
        varchar brand
    }
    PRODUCT_VARIANTS {
        int variant_id PK
        int product_id FK
        varchar sku UK
        jsonb attributes
        numeric price
    }
    INVENTORY {
        int variant_id PK, FK
        int quantity_on_hand
        int reorder_level
    }
    ORDERS {
        int order_id PK
        int customer_id FK
        int shipping_address_id FK
        varchar order_status
        timestamptz order_date
    }
    ORDER_ITEMS {
        int order_id PK, FK
        int variant_id PK, FK
        int quantity
        numeric unit_price
    }
    PAYMENTS {
        int payment_id PK
        int order_id FK
        numeric amount
        varchar payment_method
        varchar payment_status
        varchar reference UK
    }
    DELIVERY_AGENTS {
        int agent_id PK
        varchar full_name
        varchar phone UK
    }
    SHIPMENTS {
        int shipment_id PK
        int order_id FK, UK
        int agent_id FK
        varchar tracking_number UK
        varchar shipment_status
    }
    DELIVERY_EVENTS {
        bigint event_id PK
        int shipment_id FK
        varchar event_status
        timestamptz event_time
    }
```

## Keys and constraints summary

| Type | Where it is used | Business rule it protects |
|---|---|---|
| Primary keys | Every table (composite on `order_items`) | Each record is uniquely identifiable; a variant appears once per order |
| Foreign keys | 13 relationships (see diagram) | No order for a missing customer, no item for a missing product |
| `UNIQUE` | email, phone, sku, payment reference, tracking number | No duplicate accounts, products, payments or parcels |
| `CHECK` | prices > 0, stock ≥ 0, quantity > 0, allowed status values, delivery after dispatch, attributes is a JSON object | Invalid business data is impossible |
| Partial unique index | `addresses (customer_id) WHERE is_default` | At most one default address per customer |
| `ON DELETE RESTRICT` | orders → customers | Order history is never lost |
| `ON DELETE CASCADE` | items, payments, shipments, events | Removing an order removes its dependent records |

## Normalisation

See [normalisation.md](normalisation.md) for the full walk-through from UNF to 3NF/BCNF.

## Evidence

| Screenshot | Shows |
|---|---|
| `evidence/p1-tables-created.png` | The 12 tables in pgAdmin after running the schema |
| `evidence/p1-seed-row-counts.png` | Row counts printed by the seed script |
| `evidence/p1-constraint-tests.png` | All 11 constraint tests passing |
| `evidence/p1-sample-data.png` | Sample product variants with JSONB attributes |
