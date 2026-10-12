// =====================================================================
// ShopNaija — Indexes and explain() in MongoDB (compare Portfolio 2)
// MIT 8103 Advanced Database Systems — Portfolio 4
//
// Run from inside the portfolio-4-nosql folder:
//     mongosh shopnaija --quiet --file 05_indexes_explain.js
// Safe to re-run: it removes its own indexes first.
//
// COLLSCAN = read every document in the collection (like a Seq Scan)
// IXSCAN   = use an index to jump to matching documents (like an Index Scan)
// FETCH    = load the full documents the index pointed to
// =====================================================================

const line = (title) => print(`\n==================================================================\n${title}\n==================================================================`);

// Summarise the parts of explain("executionStats") that matter
function summary(label, explained) {
  if (!explained.queryPlanner || !explained.executionStats) {
    print(`${label}: unexpected explain() format, full output below`);
    printjson(explained);
    return;
  }
  let plan = explained.queryPlanner.winningPlan;
  if (plan.queryPlan) plan = plan.queryPlan;          // newer MongoDB versions nest the plan
  const stages = [];
  (function walk(p) {
    if (!p) return;
    stages.push(p.stage + (p.indexName ? `(${p.indexName})` : ''));
    walk(p.inputStage);
    (p.inputStages || []).forEach(walk);
  })(plan);
  const s = explained.executionStats;
  print(`${label.padEnd(7)} plan: ${stages.join(' <- ')}`);
  print(`        returned ${s.nReturned} | documents examined ${s.totalDocsExamined} | index keys examined ${s.totalKeysExamined} | time ${s.executionTimeMillis} ms`);
}

// Start from a clean state (keeps only the built-in _id index)
db.orders.dropIndexes();
db.products.dropIndexes();

// ---------------------------------------------------------------------
line('Q1  Customer 2955 order history, newest first');
// ---------------------------------------------------------------------
const q1 = () => db.orders.find({ customer_id: 2955 }).sort({ order_date: -1 }).explain('executionStats');
summary('BEFORE', q1());
db.orders.createIndex({ customer_id: 1, order_date: -1 }, { name: 'idx_customer_date' });
summary('AFTER', q1());

// ---------------------------------------------------------------------
line('Q2  Track a parcel by tracking number (field inside an embedded document)');
// ---------------------------------------------------------------------
const q2 = () => db.orders.find({ 'shipment.tracking_number': 'SNG000000001' }).explain('executionStats');
summary('BEFORE', q2());
// Unique, but only for orders that HAVE a shipment (partial index):
// pending orders have no tracking number and must not count as duplicates.
db.orders.createIndex(
  { 'shipment.tracking_number': 1 },
  { name: 'idx_tracking', unique: true, partialFilterExpression: { 'shipment.tracking_number': { $exists: true } } }
);
summary('AFTER', q2());

// ---------------------------------------------------------------------
line('Q3  Products with a 256GB / 16GB RAM variant (index on fields INSIDE an array)');
// ---------------------------------------------------------------------
const q3 = () => db.products.find({
  variants: { $elemMatch: { 'attributes.storage_gb': 256, 'attributes.ram_gb': 16 } }
}).explain('executionStats');
summary('BEFORE', q3());
// A "multikey" index: MongoDB adds one index entry per array element,
// so every variant of every product is indexed separately.
db.products.createIndex(
  { 'variants.attributes.storage_gb': 1, 'variants.attributes.ram_gb': 1 },
  { name: 'idx_variant_storage_ram' }
);
summary('AFTER', q3());

// ---------------------------------------------------------------------
line('Indexes now in place');
// ---------------------------------------------------------------------
['orders', 'products'].forEach(c => {
  db.getCollection(c).getIndexes().forEach(ix =>
    print(`${c.padEnd(9)} ${ix.name.padEnd(26)} ${JSON.stringify(ix.key)}${ix.unique ? '  unique' : ''}${ix.partialFilterExpression ? '  partial' : ''}`));
});
