// =====================================================================
// ShopNaija — Keep taking orders while the primary crashes
//   docker exec mongo2 mongosh --nodb --quiet --file /scripts/04_failover_writer.js
// (run from mongo2, because mongo1 is the server we will kill)
//
// Writes one "order" per second for 45 seconds and reports how long each
// write took and which server was primary. While it runs, kill the
// primary from a second terminal:  docker kill mongo1
// =====================================================================
load('/scripts/common.js');

// retryWrites (on by default) lets the driver retry a write once after
// a failover, so an order placed during the election is not lost.
const db = connect(RS_URI + '&retryWrites=true');
db.failover_test.drop();

line('Placing one order per second. Kill the primary at about order #10.');
print('time      order  result   took (ms)  primary');
for (let i = 1; i <= 45; i++) {
  const started = Date.now();
  let result, primary = '?';
  try {
    db.failover_test.insertOne(
      { _id: i, customer_id: 2955, total: 72600, placed_at: new Date() },
      { writeConcern: { w: 'majority', wtimeout: 15000 } }
    );
    result = 'OK';
    try { primary = db.hello().primary; } catch (e) { /* ignore */ }
  } catch (e) {
    result = 'FAILED';
    primary = e.message.split('\n')[0].substring(0, 70);
  }
  const took = Date.now() - started;
  print(`${clock()}  #${String(i).padStart(2)}    ${result.padEnd(7)}  ${String(took).padStart(8)}   ${primary}`);
  sleep(Math.max(0, 1000 - took));
}

line('Result');
const saved = db.failover_test.countDocuments({});
print(`Orders attempted: 45 | orders safely stored: ${saved} | lost: ${45 - saved}`);
print(`Primary now: ${db.hello().primary}`);
