// =====================================================================
// ShopNaija — Reports with the aggregation pipeline
// MIT 8103 Advanced Database Systems — Portfolio 4
//
// Run from inside the portfolio-4-nosql folder:
//     mongosh shopnaija --quiet --file 04_aggregation.js
//
// An aggregation pipeline is a list of stages. Documents flow through
// each stage in turn: filter ($match) -> reshape ($unwind, $project)
// -> summarise ($group) -> order ($sort).
// =====================================================================

const line = (title) => print(`\n==================================================================\n${title}\n==================================================================`);
const naira = (n) => Math.round(n).toLocaleString('en-NG');

// ---------------------------------------------------------------------
line('A  Revenue by category, 2026 (excluding cancelled orders)');
// ---------------------------------------------------------------------
// $unwind turns one order with 3 items into 3 documents, one per item,
// so each item can be added to its own category's total.
db.orders.aggregate([
  { $match: { status: { $ne: 'cancelled' }, order_date: { $gte: ISODate('2026-01-01T00:00:00+01:00') } } },
  { $unwind: '$items' },
  { $group: {
      _id: '$items.category',
      units: { $sum: '$items.quantity' },
      revenue_ngn: { $sum: { $multiply: ['$items.quantity', '$items.unit_price'] } }
  } },
  { $sort: { revenue_ngn: -1 } }
]).forEach(r => print(`${String(r._id).padEnd(16)} units ${String(r.units).padStart(6)}   revenue NGN ${naira(r.revenue_ngn).padStart(16)}`));

print('\nCross-check: run this in pgAdmin. The figures must match exactly.');
print(`  SELECT parent.name, SUM(oi.quantity) AS units, SUM(oi.quantity * oi.unit_price) AS revenue
  FROM orders o JOIN order_items oi USING (order_id)
  JOIN product_variants v USING (variant_id) JOIN products p USING (product_id)
  JOIN categories child ON child.category_id = p.category_id
  JOIN categories parent ON parent.category_id = child.parent_category_id
  WHERE o.order_status <> 'cancelled' AND o.order_date >= '2026-01-01 00:00:00+01'
  GROUP BY parent.name ORDER BY revenue DESC;`);

// ---------------------------------------------------------------------
line('B  Monthly revenue since August 2026 (compare Portfolio 2, Q6)');
// ---------------------------------------------------------------------
// Each order already stores its own total, so no $unwind and no join:
// one pass over the orders collection.
db.orders.aggregate([
  { $match: { status: { $ne: 'cancelled' }, order_date: { $gte: ISODate('2026-08-01T00:00:00+01:00') } } },
  { $group: {
      _id: { $dateToString: { format: '%Y-%m', date: '$order_date', timezone: 'Africa/Lagos' } },
      orders: { $sum: 1 },
      revenue_ngn: { $sum: '$total' }
  } },
  { $sort: { _id: 1 } }
]).forEach(r => print(`${r._id}   orders ${String(r.orders).padStart(6)}   revenue NGN ${naira(r.revenue_ngn).padStart(16)}`));

// ---------------------------------------------------------------------
line('C  Top 5 customers by spend ($lookup = a join, used only when needed)');
// ---------------------------------------------------------------------
db.orders.aggregate([
  { $match: { status: { $ne: 'cancelled' } } },
  { $group: { _id: '$customer_id', orders: { $sum: 1 }, spent: { $sum: '$total' } } },
  { $sort: { spent: -1 } },
  { $limit: 5 },
  { $lookup: { from: 'customers', localField: '_id', foreignField: '_id', as: 'customer' } },
  { $unwind: '$customer' },
  { $project: {
      _id: 0,
      customer_id: '$_id',
      name: { $concat: ['$customer.first_name', ' ', '$customer.last_name'] },
      email: '$customer.email',
      orders: 1,
      spent: 1
  } }
]).forEach(r => print(`#${String(r.customer_id).padEnd(5)} ${r.name.padEnd(22)} ${String(r.orders).padStart(3)} orders   NGN ${naira(r.spent).padStart(14)}   ${r.email}`));

// ---------------------------------------------------------------------
line('D  Average delivery time by destination state (hours from order to doorstep)');
// ---------------------------------------------------------------------
db.orders.aggregate([
  { $match: { 'shipment.delivered_at': { $type: 'date' } } },   // only parcels that have been delivered
  { $group: {
      _id: '$shipping_address.state',
      deliveries: { $sum: 1 },
      avg_hours: { $avg: { $divide: [{ $subtract: ['$shipment.delivered_at', '$order_date'] }, 3600000] } }
  } },
  { $sort: { avg_hours: 1 } }
]).forEach(r => print(`${String(r._id).padEnd(14)} ${String(r.deliveries).padStart(6)} deliveries   avg ${r.avg_hours.toFixed(1).padStart(5)} hours`));

// ---------------------------------------------------------------------
line('E  "Customers who bought a Phone also bought..." (relationship query)');
// ---------------------------------------------------------------------
// Find every order containing a phone, then count the OTHER subcategories
// that appear in the same orders. A graph database (e.g. Neo4j) would model
// this natively as Customer -BOUGHT-> Product relationships.
db.orders.aggregate([
  { $match: { 'items.subcategory': 'Phones' } },
  { $unwind: '$items' },
  { $match: { 'items.subcategory': { $ne: 'Phones' } } },
  { $group: { _id: '$items.subcategory', orders_together: { $sum: 1 } } },
  { $sort: { orders_together: -1 } },
  { $limit: 5 }
]).forEach(r => print(`${String(r._id).padEnd(20)} bought alongside a phone ${r.orders_together} times`));
print('(The sample data is randomly generated, so the counts are similar. Real shop data would show genuine patterns, e.g. phones with phone cases.)');
