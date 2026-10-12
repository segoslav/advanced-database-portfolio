// =====================================================================
// ShopNaija — Multi-document transaction (needs a replica set)
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/07_transaction.js
//
// Placing an order changes TWO collections: reduce stock in "products"
// AND create the order in "orders". Portfolio 4 could only make each
// change atomic on its own. A transaction makes them succeed or fail
// together, like BEGIN ... COMMIT in Portfolio 3.
// =====================================================================
load('/scripts/common.js');

const db = connect(RS_URI);
const SKU = 'FLASH-001';

if (!db.products.findOne({ 'variants.sku': SKU })) {
  print(`${SKU} not found. Load the data first (02_load_shopnaija.js).`);
  quit();
}
db.products.updateOne({ 'variants.sku': SKU }, { $set: { 'variants.$.stock.on_hand': 1 } }, { writeConcern: { w: 'majority' } });
db.orders.deleteMany({ note: 'P5 transaction demo' }, { writeConcern: { w: 'majority' } });

const stockNow = () => db.products.findOne({ 'variants.sku': SKU }, { 'variants.$': 1 }).variants[0].stock.on_hand;

function placeOrder(customerId) {
  const session = db.getMongo().startSession();
  const sdb = session.getDatabase('shopnaija');
  print(`\nCustomer ${customerId}: starting transaction (stock before: ${stockNow()})`);
  session.startTransaction({ readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' } });
  try {
    // Step 1: reduce stock, only if at least one is left
    const r = sdb.products.updateOne(
      { variants: { $elemMatch: { sku: SKU, 'stock.on_hand': { $gte: 1 } } } },
      { $inc: { 'variants.$.stock.on_hand': -1 } }
    );
    if (r.modifiedCount !== 1) throw new Error('Out of stock');
    print('  step 1: stock reduced (inside the transaction)');

    // Step 2: create the order
    const ins = sdb.orders.insertOne({
      customer_id: customerId, status: 'paid', order_date: new Date(), note: 'P5 transaction demo',
      items: [{ sku: SKU, product_name: 'Tecno Phantom X Flash Sale', quantity: 1, unit_price: 250000 }],
      total: 250000
    });
    print('  step 2: order created (inside the transaction)');

    // Isolation: outside the transaction, nobody can see the order yet
    const visible = db.orders.findOne({ _id: ins.insertedId });
    print(`  before COMMIT, visible to other users? ${visible ? 'YES' : 'NO'}`);

    session.commitTransaction();
    print(`  COMMITTED. Order ${ins.insertedId} now visible? ${db.orders.findOne({ _id: ins.insertedId }) ? 'YES' : 'NO'}`);
  } catch (e) {
    session.abortTransaction();
    print(`  ABORTED (${e.message}). Every change in this transaction was undone.`);
  } finally {
    session.endSession();
  }
  print(`  stock after: ${stockNow()}`);
}

line('Two customers try to buy the last flash-sale phone');
placeOrder(1);
placeOrder(2);

line('Result');
print(`Flash-sale orders stored: ${db.orders.countDocuments({ note: 'P5 transaction demo' })} | stock left: ${stockNow()}`);
