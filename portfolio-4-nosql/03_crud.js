// =====================================================================
// ShopNaija — CRUD operations on the document model
// MIT 8103 Advanced Database Systems — Portfolio 4
//
// Run from inside the portfolio-4-nosql folder:
//     mongosh shopnaija --quiet --file 03_crud.js
// Safe to re-run.
// =====================================================================

const line = (title) => print(`\n==================================================================\n${title}\n==================================================================`);

// ---------------------------------------------------------------------
// CREATE — a product with attributes no existing product has
// ---------------------------------------------------------------------
line('CREATE 1  Add a solar generator (new attribute types, no ALTER TABLE)');
db.products.deleteMany({ _id: 900001 });            // makes the script re-runnable

const created = db.products.insertOne({
  _id: 900001,
  name: 'Lumos Solar Generator 1500W',
  brand: 'Lumos',
  description: 'Portable solar power station for homes and small shops.',
  is_active: true,
  created_at: new Date(),
  category: { name: 'Solar & Power', parent: 'Electronics' },
  variants: [{
    sku: 'SOLAR-1500-1',
    attributes: {
      wattage_w: 1500,
      battery_type: 'LiFePO4',
      battery_capacity_wh: 1536,
      solar_input_w: 500,
      outlets: ['AC', 'USB-C', '12V car socket']    // a list inside an attribute
    },
    price: 1250000,
    stock: { on_hand: 15, reorder_level: 3 }
  }]
});
print(`Inserted product _id: ${created.insertedId}`);
print('In SQL this needed either new columns or a JSONB column (Portfolio 1). Here it is just a new document.');

line('CREATE 2  Schema validation still rejects bad data');
try {
  const bad = db.orders.insertOne({
    customer_id: 1, status: 'lost_in_space', order_date: new Date(),
    items: [{ sku: 'SKU-1-1', quantity: 0, unit_price: 934100 }], total: 0
  });
  print('FAIL: invalid order was accepted (are the validators missing?)');
  db.orders.deleteOne({ _id: bad.insertedId });
} catch (e) {
  if (e.code === 121) {   // 121 = DocumentValidationFailure
    print(`PASS: invalid order rejected -> ${e.message.split('\n')[0]}`);
    print('(status "lost_in_space" is not in the allowed list and quantity 0 is below the minimum of 1)');
  } else {
    print(`Unexpected error: ${e.message}`);
  }
}

// ---------------------------------------------------------------------
// READ
// ---------------------------------------------------------------------
line('READ 1  Same collection, different shapes: a phone vs a bag of rice vs the generator');
const shape = { _id: 0, name: 1, 'category.name': 1, 'variants.attributes': 1 };
printjson(db.products.findOne({ 'category.name': 'Phones' }, shape));
printjson(db.products.findOne({ 'category.name': 'Food Staples' }, shape));
printjson(db.products.findOne({ _id: 900001 }, shape));

line('READ 2  Phones with a 256GB / 16GB RAM variant (search inside the embedded array)');
const phoneFilter = {
  'category.name': 'Phones',
  variants: { $elemMatch: { 'attributes.storage_gb': 256, 'attributes.ram_gb': 16 } }
};
print(`Matching phones: ${db.products.countDocuments(phoneFilter)}`);
db.products.find(phoneFilter, { _id: 0, name: 1, 'variants.$': 1 }).limit(3).forEach(printjson);

line('READ 3  Track a parcel: ONE read, no joins (SQL needed shipments JOIN delivery_events)');
printjson(db.orders.findOne(
  { 'shipment.tracking_number': 'SNG000000001' },
  { _id: 1, status: 1, 'shipment.tracking_number': 1, 'shipment.status': 1, 'shipment.events': 1 }
));

line('READ 4  Customer 2955: five most recent orders');
db.orders.find({ customer_id: 2955 }, { _id: 1, status: 1, order_date: 1, total: 1 })
  .sort({ order_date: -1 }).limit(5).forEach(printjson);

// ---------------------------------------------------------------------
// UPDATE
// ---------------------------------------------------------------------
line('UPDATE 1  Change the price of one variant inside a product (positional $ operator)');
const before = db.products.findOne({ 'variants.sku': 'SKU-5-1' }, { _id: 0, name: 1, 'variants.$': 1 });
db.products.updateOne({ 'variants.sku': 'SKU-5-1' }, { $inc: { 'variants.$.price': 1000 } });
const after = db.products.findOne({ 'variants.sku': 'SKU-5-1' }, { _id: 0, name: 1, 'variants.$': 1 });
print(`${before.name} (SKU-5-1): price ${before.variants[0].price} -> ${after.variants[0].price}`);
db.products.updateOne({ 'variants.sku': 'SKU-5-1' }, { $inc: { 'variants.$.price': -1000 } });   // put it back
print('(price restored afterwards so the script can be re-run)');

line('UPDATE 2  Rider scans a parcel: add a tracking event and change its status');
const parcel = db.orders.findOne({ 'shipment.status': 'in_transit' }, { _id: 1, 'shipment.tracking_number': 1 });
if (parcel) {
  db.orders.updateOne(
    { _id: parcel._id },
    {
      $set:  { 'shipment.status': 'out_for_delivery' },
      $push: { 'shipment.events': { status: 'out_for_delivery', location: 'Abuja', time: new Date(), note: 'Rider is on the way' } }
    }
  );
  const updated = db.orders.findOne({ _id: parcel._id }, { shipment: 1 });
  print(`Order ${parcel._id}, parcel ${updated.shipment.tracking_number}: status now "${updated.shipment.status}"`);
  print('Last two tracking events:');
  printjson(updated.shipment.events.slice(-2));
} else {
  print('No parcels currently in transit.');
}

line('UPDATE 3  Flash sale: one phone left, two customers (compare Portfolio 3)');
const flash = db.products.findOne({ 'variants.sku': 'FLASH-001' }, { _id: 1 });
if (!flash) {
  print('FLASH-001 not found. Run Portfolio 3 00_setup.sql, then re-export and reload.');
} else {
  db.products.updateOne({ 'variants.sku': 'FLASH-001' }, { $set: { 'variants.$.stock.on_hand': 1 } });

  // The condition (stock >= 1) and the decrement happen in ONE atomic
  // operation on ONE document, so two buyers can never both succeed.
  const buyLastPhone = (customer) => {
    const r = db.products.updateOne(
      { variants: { $elemMatch: { sku: 'FLASH-001', 'stock.on_hand': { $gte: 1 } } } },
      { $inc: { 'variants.$.stock.on_hand': -1 } }
    );
    print(`Customer ${customer}: modifiedCount = ${r.modifiedCount} -> ${r.modifiedCount === 1 ? 'GOT THE PHONE' : 'SOLD OUT'}`);
  };
  buyLastPhone(1);
  buyLastPhone(2);
  const left = db.products.findOne({ 'variants.sku': 'FLASH-001' }, { _id: 0, 'variants.$': 1 });
  print(`Stock left: ${left.variants[0].stock.on_hand}`);
}

// ---------------------------------------------------------------------
// DELETE
// ---------------------------------------------------------------------
line('DELETE  Remove the demo solar generator');
const deleted = db.products.deleteOne({ _id: 900001 });
print(`deletedCount: ${deleted.deletedCount}`);
