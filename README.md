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

## Repository Structure
| Folder | Portfolio | Status |
|---|---|---|
| `portfolio-1-database-design/` | Database Design and Modelling | Completed |
| `portfolio-2-query-optimisation/` | Query Processing and Optimisation | Completed |
| `portfolio-3-transactions-concurrency/` | Transactions and Concurrency | Planned |
| `portfolio-4-nosql/` | NoSQL and Advanced Data Models | Planned |
| `portfolio-5-distributed-cloud/` | Distributed and Cloud Databases | Planned |
| `evidence/` | Setup screenshots and general evidence | — |

## Tools Used
PostgreSQL, pgAdmin, MongoDB, MongoDB Compass, Docker Desktop, Python, Git, VS Code.