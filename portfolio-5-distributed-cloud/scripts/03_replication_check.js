// =====================================================================
// ShopNaija — Watch one write travel to every member
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/03_replication_check.js
// =====================================================================
load('/scripts/common.js');

const db = connect(RS_URI);
const primaryHost = db.hello().primary;
const key = `ORDER-REPL-${Date.now()}`;

line('1  Write one new order to the PRIMARY (writeConcern w:1 = primary only)');
db.replication_test.insertOne(
  { _id: key, customer_id: 2955, status: 'paid', total: 72600, created_at: new Date() },
  { writeConcern: { w: 1 } }
);
print(`${clock()}  wrote ${key} to ${primaryHost}`);

line('2  Look for it on each member separately');
HOSTS.forEach(h => {
  const d = direct(h);
  let found = null, waited = 0;
  while (!found && waited < 5000) {
    found = d.replication_test.findOne({ _id: key });
    if (!found) { sleep(20); waited += 20; }
  }
  const role = d.hello().isWritablePrimary ? 'PRIMARY  ' : 'SECONDARY';
  print(`${h.padEnd(15)} ${role}  ${found ? 'FOUND' : 'NOT FOUND'}  (after about ${waited} ms)`);
});

line('3  How it travelled: the oplog entry on the primary');
// Secondaries copy the primary's operation log (oplog) and replay it.
const op = direct(primaryHost, 'local').oplog.rs.find({ 'o._id': key })
  .sort({ $natural: -1 }).limit(1).toArray()[0];     // newest entries first
if (op) {
  printjson({ ts: op.ts, op: op.op === 'i' ? 'i (insert)' : op.op, ns: op.ns, o: op.o });
} else {
  print('Oplog entry not found.');
}

line('4  Replication lag: how far behind the primary each member is');
const s = direct(primaryHost, 'admin').runCommand({ replSetGetStatus: 1 });
const p = s.members.find(m => m.stateStr === 'PRIMARY');
s.members.forEach(m => {
  const lag = (p && m.optimeDate) ? (p.optimeDate - m.optimeDate) / 1000 : NaN;
  print(`${m.name.padEnd(15)} ${String(m.stateStr).padEnd(10)} behind primary by ${isNaN(lag) ? '-' : lag + ' s'}`);
});
