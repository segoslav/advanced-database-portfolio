// =====================================================================
// ShopNaija — Choosing a shard key, using the real order data
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/08_shard_key_analysis.js
//
// Sharding splits ONE collection across several servers (shards) so that
// no single server has to hold or write all the data. The shard key decides
// which shard each order lives on. This script measures how three candidate
// keys would spread ShopNaija's 100,000 orders across 3 shards.
// =====================================================================
load('/scripts/common.js');

const db = connect(RS_URI);
const total = db.orders.countDocuments({});
const pct = (n) => (100 * n / total).toFixed(1) + '%';

line('Option A  shard key { "shipping_address.state": 1 }  (by delivery state)');
const states = db.orders.aggregate([
  { $group: { _id: '$shipping_address.state', orders: { $sum: 1 } } },
  { $sort: { orders: -1 } }
]).toArray();
states.slice(0, 5).forEach(s => print(`${String(s._id).padEnd(14)} ${String(s.orders).padStart(6)} orders  ${pct(s.orders)}`));
print(`... ${states.length} distinct states in total`);
const avg = total / states.length;
print(`Busiest state (${states[0]._id}) has ${(states[0].orders / avg).toFixed(1)}x the orders of an average state:`);
print('whichever shard holds it becomes overloaded. And with only ' + states.length + ' possible key values,');
print(`the data can never be split into more than ${states.length} pieces, however much the shop grows.`);

line('Option B  shard key { order_date: 1 }  (by date, ranged)');
const months = db.orders.aggregate([
  { $group: { _id: { $dateToString: { format: '%Y-%m', date: '$order_date', timezone: 'Africa/Lagos' } }, orders: { $sum: 1 } } },
  { $sort: { _id: -1 } },
  { $limit: 3 }
]).toArray();
months.forEach(m => print(`${m._id}  ${String(m.orders).padStart(6)} orders`));
print('Dates only ever increase, so EVERY new order lands on the shard holding "the latest dates".');
print('One shard takes all the writes (a "hot shard") while the others sit idle.');

line('Option C  shard key { customer_id: "hashed" }  (recommended)');
// Simulated with customer_id mod 3. A real hashed key scrambles the value
// so that consecutive customers spread evenly in the same way.
db.orders.aggregate([
  { $group: { _id: { $mod: ['$customer_id', 3] }, orders: { $sum: 1 }, customers: { $addToSet: '$customer_id' } } },
  { $project: { orders: 1, customers: { $size: '$customers' } } },
  { $sort: { _id: 1 } }
]).forEach(s => print(`shard ${s._id + 1}: ${String(s.orders).padStart(6)} orders (${pct(s.orders)}) from ${s.customers} customers`));
print('Even spread of data AND of new writes, and the most common query, "show MY orders",');
print('goes to exactly one shard because all of a customer\'s orders share a key.');

line('Commands that would apply it on a sharded cluster (not run here)');
print(`  sh.enableSharding("shopnaija")
  db.orders.createIndex({ customer_id: "hashed" })
  sh.shardCollection("shopnaija.orders", { customer_id: "hashed" })`);
