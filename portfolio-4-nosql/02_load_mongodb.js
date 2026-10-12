// =====================================================================
// ShopNaija — Load the exported documents into MongoDB
// MIT 8103 Advanced Database Systems — Portfolio 4
//
// Run from inside the portfolio-4-nosql folder:
//     mongosh shopnaija --quiet --file 02_load_mongodb.js
//
// Safe to re-run: it drops and recreates the three collections.
// Takes 1-3 minutes (100,000 orders).
// =====================================================================

const fs = require('fs');
const { StringDecoder } = require('string_decoder');

// ---------------------------------------------------------------------
// 1. Schema validation rules.
//    "Schemaless" does not have to mean "no rules": MongoDB can still
//    reject bad documents, much like the CHECK constraints in Portfolio 1.
//    Unlike SQL, these rules only cover the fields we care about, so
//    products in different categories can still carry different attributes.
// ---------------------------------------------------------------------
const productRules = {
  $jsonSchema: {
    bsonType: 'object',
    required: ['name', 'category', 'variants'],
    properties: {
      name:     { bsonType: 'string' },
      category: { bsonType: 'object', required: ['name'] },
      variants: {
        bsonType: 'array',
        minItems: 1,
        items: {
          bsonType: 'object',
          required: ['sku', 'price', 'stock'],
          properties: {
            sku:        { bsonType: 'string' },
            attributes: { bsonType: 'object' },          // contents are free-form
            price:      { bsonType: 'number', minimum: 0, exclusiveMinimum: true },
            stock: {
              bsonType: 'object',
              required: ['on_hand'],
              properties: { on_hand: { bsonType: 'number', minimum: 0 } }
            }
          }
        }
      }
    }
  }
};

const customerRules = {
  $jsonSchema: {
    bsonType: 'object',
    required: ['first_name', 'last_name', 'email', 'phone'],
    properties: {
      email:     { bsonType: 'string', pattern: '^.+@.+\\..+$' },
      addresses: { bsonType: 'array' }
    }
  }
};

const orderRules = {
  $jsonSchema: {
    bsonType: 'object',
    required: ['customer_id', 'status', 'order_date', 'items', 'total'],
    properties: {
      status:     { enum: ['pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled'] },
      order_date: { bsonType: 'date' },
      total:      { bsonType: 'number', minimum: 0 },
      items: {
        bsonType: 'array',
        minItems: 1,
        items: {
          bsonType: 'object',
          required: ['sku', 'quantity', 'unit_price'],
          properties: {
            quantity:   { bsonType: 'number', minimum: 1 },
            unit_price: { bsonType: 'number', minimum: 0, exclusiveMinimum: true }
          }
        }
      }
    }
  }
};

// ---------------------------------------------------------------------
// 2. Helpers
// ---------------------------------------------------------------------

// PostgreSQL writes dates as text, e.g. "2026-09-01T07:15:23.905442+01:00".
// Turn those back into real dates so MongoDB can sort and compare them.
const isoDate = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
function reviveDates(key, value) {
  return (typeof value === 'string' && isoDate.test(value)) ? new Date(value) : value;
}

// Read a JSON Lines file a few MB at a time (the orders file is ~150 MB,
// too big to load into memory in one go) and insert in batches.
function loadJsonLines(file, collection, batchSize) {
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.alloc(4 * 1024 * 1024);
  const decoder = new StringDecoder('utf8');
  let leftover = '';
  let batch = [];
  let total = 0;

  const flush = () => {
    if (batch.length) {
      db.getCollection(collection).insertMany(batch, { ordered: false });
      total += batch.length;
      batch = [];
    }
  };
  const handle = (line) => {
    line = line.trim();
    if (line) {
      batch.push(JSON.parse(line, reviveDates));
      if (batch.length >= batchSize) flush();
    }
  };

  let bytesRead;
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

// ---------------------------------------------------------------------
// 3. Recreate the collections with their rules, then load the data
// ---------------------------------------------------------------------
print('Recreating collections with validation rules...');
['products', 'customers', 'orders'].forEach(name => db.getCollection(name).drop());
db.createCollection('products',  { validator: productRules,  validationLevel: 'strict', validationAction: 'error' });
db.createCollection('customers', { validator: customerRules, validationLevel: 'strict', validationAction: 'error' });
db.createCollection('orders',    { validator: orderRules,    validationLevel: 'strict', validationAction: 'error' });

const started = Date.now();
print('Loading products...');
const nProducts  = loadJsonLines('data/products.jsonl',  'products',  1000);
print('Loading customers...');
const nCustomers = loadJsonLines('data/customers.jsonl', 'customers', 1000);
print('Loading orders (the big one)...');
const nOrders    = loadJsonLines('data/orders.jsonl',    'orders',    2000);
const seconds = ((Date.now() - started) / 1000).toFixed(1);

// ---------------------------------------------------------------------
// 4. Summary: compare these counts with the PostgreSQL tables
// ---------------------------------------------------------------------
print('\n================ LOAD SUMMARY ================');
print(`products  : ${nProducts} documents  (SQL: products + categories + product_variants + inventory)`);
print(`customers : ${nCustomers} documents  (SQL: customers + addresses)`);
print(`orders    : ${nOrders} documents  (SQL: orders + order_items + payments + shipments + delivery_agents + delivery_events)`);
print(`Loaded in ${seconds} seconds`);

print('\nAverage document size (bytes):');
['products', 'customers', 'orders'].forEach(name => {
  try {
    const s = db.getCollection(name).aggregate([{ $collStats: { storageStats: {} } }]).toArray()[0];
    print(`  ${name.padEnd(10)}: ${s.storageStats.avgObjSize}`);
  } catch (e) {
    print(`  ${name.padEnd(10)}: (not available)`);
  }
});

print('\nOne complete order document: what took 6 tables and 5 joins in SQL');
printjson(db.orders.findOne({ status: 'delivered' }));
