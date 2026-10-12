// =====================================================================
// ShopNaija — Network partition, part A: write on the majority side
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/06a_partition_write.js
// Run this AFTER cutting mongo3 off the network:
//   docker network disconnect shopnaija-net mongo3
// =====================================================================
load('/scripts/common.js');

const db = connect(RS_URI);

line('1  The cluster from the primary\'s point of view');
printMembers(direct(db.hello().primary, 'admin'));

db.partition_test.deleteMany({}, { writeConcern: { w: 'majority', wtimeout: 10000 } });

line('2  Place an order with writeConcern "majority" (needs 2 of 3 servers)');
try {
  db.partition_test.insertOne(
    { _id: 'ORDER-A', note: 'written during the partition, w: majority', at: new Date() },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print(`${clock()}  ORDER-A saved. mongo1 + mongo2 are a majority, so the shop keeps working.`);
} catch (e) {
  print(`${clock()}  ORDER-A failed: ${e.message.split('\n')[0]}`);
}

line('3  Place an order with writeConcern 3 (needs ALL servers)');
const started = Date.now();
try {
  db.partition_test.insertOne(
    { _id: 'ORDER-B', note: 'written during the partition, w: 3', at: new Date() },
    { writeConcern: { w: 3, wtimeout: 5000 } }
  );
  print(`${clock()}  ORDER-B confirmed by all three servers.`);
} catch (e) {
  print(`${clock()}  ORDER-B NOT confirmed after ${Date.now() - started} ms: ${(e.codeName || '')} ${e.message.split('\n')[0]}`);
  print('  mongo3 is unreachable, so "all three" can never confirm.');
  print('  Note: the order IS stored on the primary; only the confirmation timed out.');
}
print(`\nOrders on the majority side now: ${db.partition_test.countDocuments({})}`);
