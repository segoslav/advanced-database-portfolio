# Normalisation — ShopNaija Online Marketplace

This document shows how the ShopNaija schema was reached by normalising a single
"flat" order record step by step: **UNF → 1NF → 2NF → 3NF**, followed by a BCNF check
and the deliberate design decisions that go beyond the normal forms.

---

## 1. Starting point — Unnormalised Form (UNF)

Imagine ShopNaija kept every order in one spreadsheet row:

| order_id | order_date | customer_name | customer_email | customer_phone | delivery_address | items | payment | delivery_status |
|---|---|---|---|---|---|---|---|---|
| 1001 | 2026-09-02 | Ngozi Okafor | ngozi@example.com | 08031234567 | 12 Allen Ave, Ikeja, Lagos | Tecno Spark 20 (128GB, Black) x1 @ ₦185,000; Milo 1kg x2 @ ₦6,500 | card, ₦198,000, successful | delivered |

**Problems:**
- The `items` column holds **several values in one cell** (a repeating group). It is
  impossible to ask "how many Tecno phones were sold?" without text parsing.
- Ngozi's name, email and phone are **repeated on every order she places**. If she
  changes her phone number, every old row must be updated (**update anomaly**).
- A new product cannot be recorded until someone orders it (**insertion anomaly**).
- Deleting Ngozi's only order also deletes the only record that she exists
  (**deletion anomaly**).

---

## 2. First Normal Form (1NF)

**Rule:** every cell holds a single (atomic) value, and there are no repeating groups.

The `items` list is split so each item is its own row, and the address is split into
parts. The key becomes the combination **(order_id, sku)**.

| order_id | sku | order_date | customer_email | customer_name | customer_phone | street | city | state | product_name | category | variant_attributes | unit_price | quantity | payment_method | payment_status | delivery_status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1001 | SKU-77-2 | 2026-09-02 | ngozi@example.com | Ngozi Okafor | 08031234567 | 12 Allen Ave | Ikeja | Lagos | Tecno Spark 20 | Phones | 128GB, Black | 185,000 | 1 | card | successful | delivered |
| 1001 | SKU-412-1 | 2026-09-02 | ngozi@example.com | Ngozi Okafor | 08031234567 | 12 Allen Ave | Ikeja | Lagos | Milo | Beverages | 1kg | 6,500 | 2 | card | successful | delivered |

Atomic now — but customer and order details are still **repeated on every item row**.

---

## 3. Second Normal Form (2NF)

**Rule:** be in 1NF, and every non-key column must depend on the **whole** key,
not just part of it (no *partial dependencies*).

With key **(order_id, sku)**:

| Column(s) | Depends on | Partial? |
|---|---|---|
| order_date, customer details, address, payment, delivery_status | `order_id` only | ✗ partial |
| product_name, category, variant_attributes | `sku` only | ✗ partial |
| quantity, unit_price | `(order_id, sku)` — the whole key | ✓ full |

Each partial dependency is moved into its own table:

- **ORDERS**(order_id, order_date, customer_email, customer_name, customer_phone, street, city, state, payment_method, payment_status, delivery_status)
- **PRODUCT_VARIANTS**(sku, product_name, category, variant_attributes, price)
- **ORDER_ITEMS**(order_id, sku, quantity, unit_price)

---

## 4. Third Normal Form (3NF)

**Rule:** be in 2NF, and no non-key column may depend on **another non-key column**
(no *transitive dependencies*).

Remaining transitive dependencies:

| Table | Transitive dependency | Fix |
|---|---|---|
| ORDERS | order_id → customer_email → customer_name, customer_phone | Move to **CUSTOMERS** |
| ORDERS | order_id → address → street, city, state (and an address belongs to a customer, not an order) | Move to **ADDRESSES**; orders keep only `shipping_address_id` |
| ORDERS | order_id → payment details (an order can have several payment attempts) | Move to **PAYMENTS** |
| ORDERS | order_id → delivery details (agent, tracking number, tracking history) | Move to **SHIPMENTS** and **DELIVERY_EVENTS** |
| PRODUCT_VARIANTS | sku → product_name → category, brand | Move to **PRODUCTS**; then category name → parent category moves to **CATEGORIES** |
| PRODUCT_VARIANTS | stock level changes independently of the product description | Move to **INVENTORY** |

**Final 3NF schema (12 tables):**
customers, addresses, categories, products, product_variants, inventory,
orders, order_items, payments, delivery_agents, shipments, delivery_events.

Surrogate keys (`customer_id`, `variant_id`, …) replace natural keys such as email
and SKU as primary keys, because natural values can change. The natural keys are still
protected with `UNIQUE` constraints.

---

## 5. BCNF check

**Rule:** for every functional dependency X → Y, X must be a candidate key.

Each table was checked. The only determinants are the primary keys and the
`UNIQUE` columns (email, phone, sku, reference, tracking_number, shipments.order_id),
which are all candidate keys. **The schema therefore also satisfies BCNF.**

---

## 6. Deliberate design decisions

These go beyond the normal forms and were chosen for the business, not by accident.

| Decision | Why |
|---|---|
| **`order_items.unit_price` is stored**, even though `product_variants.price` exists | It is *not* redundant: it records the price **at the moment of purchase**. If a phone goes from ₦185,000 to ₦199,000 next month, old orders must still show what the customer actually paid. |
| **No `total_amount` column on `orders`** | The total can always be calculated from `order_items` (quantity × unit_price). Storing it would create a second copy that could drift out of sync. (Portfolio 2 looks at whether a materialised view is worth it for reporting.) |
| **Product attributes stored as `JSONB`** in `product_variants` | A phone has storage and RAM; a dress has size and material; rice has weight. A fixed column for every possible attribute would leave most cells empty, and an attribute-value (EAV) table makes simple queries complex. JSONB keeps the flexibility while PostgreSQL can still search and index it (GIN index in Portfolio 2). A CHECK constraint ensures it is always a JSON object. This is a conscious, limited exception to strict 1NF atomicity, and it leads naturally into the NoSQL document model in Portfolio 4. |
| **Payments are a separate table, not columns on orders** | One order can have several payment attempts (failed card, then a successful bank transfer) and refunds. |
| **One shipment per order** (`UNIQUE` on `shipments.order_id`) | A simplifying business rule for this case study: ShopNaija ships each order in a single package. |
| **Partial unique index on default address** | Enforces "only one default address per customer" inside the database, not just in application code. |
| **`ON DELETE RESTRICT` for customers with orders** | Financial history must never disappear because a customer account was deleted. |
