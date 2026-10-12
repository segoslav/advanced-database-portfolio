// =====================================================================
// ShopNaija — Load the Portfolio 4 documents into the replica set
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/02_load_shopnaija.js
// Writes go to the PRIMARY with writeConcern "majority" (at least 2 of
// the 3 servers must have each batch before it counts as saved).
// Takes 1-3 minutes.
// =====================================================================
load('/scripts/common.js');
const fs = require('fs');
const { StringDecoder } = require('string_decoder');

const db = connect(RS_URI);

const isoDate = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
const reviveDates = (k, v) => (typeof v === 'string' && isoDate.test(v)) ? new Date(v) : v;

function loadJsonLines(file, collection, batchSize) {
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.alloc(4 * 1024 * 1024);
  const decoder = new StringDecoder('utf8');
  let leftover = '', batch = [], total = 0, bytesRead;
  const flush = () => {
    if (batch.length) {
      db.getCollection(collection).insertMany(batch, { ordered: false, writeConcern: { w: 'majority' } });
      total += batch.length;
      batch = [];
    }
  };
  const handle = (l) => {
    l = l.trim();
    if (l) { batch.push(JSON.parse(l, reviveDates)); if (batch.length >= batchSize) flush(); }
  };
  while ((bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null)) > 0) {
    const lines = (leftover + decoder.write(buffer.subarray(0, bytesRead))).split('\n');
    leftover = lines.pop();
    lines.forEach(handle);
  }
  handle(leftover + decoder.end());
  flush();
  fs.closeSync(fd);
  return total;
}

line(`Loading into the replica set (primary: ${db.hello().primary})`);
['products', 'customers', 'orders'].forEach(c => db.getCollection(c).drop());
const started = Date.now();
['products', 'customers', 'orders'].forEach(c => {
  const n = loadJsonLines(`/shopnaija-data/${c}.jsonl`, c, 2000);
  print(`${c.padEnd(10)} ${n} documents written to the primary`);
});
print(`Finished in ${((Date.now() - started) / 1000).toFixed(1)} seconds`);

db.orders.createIndex({ customer_id: 1, order_date: -1 });

line('Did every server receive a copy? (counted on each member directly)');
sleep(2000);
print('member          role        products  customers    orders');
HOSTS.forEach(h => {
  try {
    const d = direct(h);
    const role = d.hello().isWritablePrimary ? 'PRIMARY' : 'SECONDARY';
    print(`${h.padEnd(15)} ${role.padEnd(11)} ${String(d.products.countDocuments({})).padStart(8)}  ${String(d.customers.countDocuments({})).padStart(9)}  ${String(d.orders.countDocuments({})).padStart(8)}`);
  } catch (e) {
    print(`${h.padEnd(15)} unreachable (${e.message.split('\n')[0]})`);
  }
});
