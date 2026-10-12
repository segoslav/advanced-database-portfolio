// =====================================================================
// ShopNaija — Network partition, part B: what does the cut-off server see?
//   docker exec mongo3 mongosh --nodb --quiet --file /scripts/06b_read_on_mongo3.js
// Runs INSIDE mongo3, so it works even while mongo3 is cut off.
// Run it once during the partition, and again after reconnecting.
// =====================================================================
load('/scripts/common.js');

const me = direct('localhost:27017');

line(`mongo3's view of the cluster at ${clock()}`);
printMembers(me.getSiblingDB('admin'));

line('Orders that mongo3 can see');
['ORDER-A', 'ORDER-B'].forEach(id => {
  const doc = me.partition_test.find({ _id: id }).readPref('secondaryPreferred').toArray()[0];
  print(`${id}: ${doc ? 'FOUND   (' + doc.note + ')' : 'NOT FOUND  (mongo3 has not received it)'}`);
});
print(`\nmongo3 is ${me.hello().isWritablePrimary ? 'PRIMARY' : 'a SECONDARY'}: it can still answer reads, but cannot accept writes.`);
