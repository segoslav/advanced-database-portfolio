// =====================================================================
// ShopNaija — The price of safety: write concern
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/05_write_concern.js
// Run with ALL THREE members up.
//
// writeConcern says how many servers must confirm a write before the
// application is told "saved":
//   w: 1          only the primary         (fastest, can be lost in a crash)
//   w: 'majority' 2 of 3 servers           (survives losing any one server)
//   w: 3          all three servers        (safest, but fails if ANY is down)
// =====================================================================
load('/scripts/common.js');

const db = connect(RS_URI);
const N = 300;

line(`Insert ${N} orders with each write concern and time them`);
print('write concern   total ms   avg ms per write');
const results = {};
[{ w: 1 }, { w: 'majority' }, { w: 3 }].forEach(wc => {
  db.write_concern_test.drop();
  const started = Date.now();
  for (let i = 0; i < N; i++) {
    db.write_concern_test.insertOne({ n: i, total: 72600, at: new Date() }, { writeConcern: { ...wc, wtimeout: 10000 } });
  }
  const ms = Date.now() - started;
  results[wc.w] = ms;
  print(`w: ${String(wc.w).padEnd(12)} ${String(ms).padStart(8)}   ${(ms / N).toFixed(2).padStart(8)}`);
});

line('Reading it back: readConcern');
// "local"    : return whatever this server has, even if it might later be rolled back
// "majority" : return only data that a majority of servers have (cannot be rolled back)
const local = db.write_concern_test.find().readConcern('local').toArray().length;
const majority = db.write_concern_test.find().readConcern('majority').toArray().length;
print(`readConcern local: ${local} documents | readConcern majority: ${majority} documents`);
print('(Equal here because every write was already on a majority. They differ only while replication is catching up.)');
db.write_concern_test.drop();
