// =====================================================================
// ShopNaija — Key-value model: the shopping cart
// MIT 8103 Advanced Database Systems — Portfolio 4
//
// Run from inside the portfolio-4-nosql folder:
//     mongosh shopnaija --quiet --file 06_key_value_cart.js
//
// A shopping cart is a classic KEY-VALUE problem:
//   key   = the visitor's session ID
//   value = what is in their cart
// It is read and written constantly, always by its key, never joined to
// anything, and abandoned carts should simply disappear. A dedicated
// key-value store such as Redis is the usual production choice; here the
// same pattern is shown in MongoDB, using a TTL (time-to-live) index for expiry.
// =====================================================================

const line = (title) => print(`\n==================================================================\n${title}\n==================================================================`);

db.carts.drop();

// Abandoned carts are deleted automatically 30 minutes after their last change.
db.carts.createIndex({ updated_at: 1 }, { name: 'ttl_30_minutes', expireAfterSeconds: 1800 });

// PUT: add an item (creates the cart if this session has none: an "upsert")
function addToCart(sessionId, sku, qty) {
  db.carts.updateOne(
    { _id: sessionId },
    { $inc: { [`items.${sku}`]: qty }, $set: { updated_at: new Date() } },
    { upsert: true }
  );
}
// DELETE one item
function removeFromCart(sessionId, sku) {
  db.carts.updateOne({ _id: sessionId }, { $unset: { [`items.${sku}`]: '' }, $set: { updated_at: new Date() } });
}
// GET by key
const getCart = (sessionId) => db.carts.findOne({ _id: sessionId });

line('1  Visitor adds items (cart created automatically on first add)');
addToCart('sess_7f3a9c21', 'SKU-1-1', 1);
addToCart('sess_7f3a9c21', 'SKU-412-1', 2);
addToCart('sess_7f3a9c21', 'SKU-412-1', 1);      // same item again: quantity becomes 3
printjson(getCart('sess_7f3a9c21'));

line('2  Visitor removes the laptop');
removeFromCart('sess_7f3a9c21', 'SKU-1-1');
printjson(getCart('sess_7f3a9c21'));

line('3  A second visitor, a completely separate key');
addToCart('sess_b19e44d0', 'SKU-77-2', 1);
printjson(getCart('sess_b19e44d0'));

line('4  Lookup by key uses the built-in _id index (no other index needed)');
const ex = db.carts.find({ _id: 'sess_7f3a9c21' }).explain('executionStats');
if (ex.queryPlanner && ex.executionStats) {
  let plan = ex.queryPlanner.winningPlan;
  if (plan.queryPlan) plan = plan.queryPlan;
  print(`plan: ${plan.stage}${plan.inputStage ? ' <- ' + plan.inputStage.stage : ''} | documents examined: ${ex.executionStats.totalDocsExamined}`);
} else {
  printjson(ex);
}

line('5  Expiry rule');
db.carts.getIndexes().filter(ix => ix.expireAfterSeconds !== undefined)
  .forEach(ix => print(`${ix.name}: carts untouched for ${ix.expireAfterSeconds / 60} minutes are deleted automatically`));
print(`Carts right now: ${db.carts.countDocuments()}`);
