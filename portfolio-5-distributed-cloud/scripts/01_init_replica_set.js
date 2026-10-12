// =====================================================================
// ShopNaija — Create the 3-member replica set "rs0"
//   docker exec mongo1 mongosh --nodb --quiet --file /scripts/01_init_replica_set.js
// Safe to re-run: does nothing if the set already exists.
// =====================================================================
load('/scripts/common.js');

// The servers take a few seconds to start after "docker compose up", so retry.
let admin = null;
for (let i = 0; i < 30 && !admin; i++) {
  try { admin = direct('mongo1:27017', 'admin'); }
  catch (e) { print('Waiting for mongo1 to start...'); sleep(2000); }
}
if (!admin) { print('mongo1 is not answering. Check: docker compose ps'); quit(); }

function alreadyInitiated() {
  try { return admin.runCommand({ replSetGetStatus: 1 }).ok === 1; }
  catch (e) { return false; }      // "no replset config has been received"
}

line('Step 1  Initiate the replica set');
if (alreadyInitiated()) {
  print('Replica set rs0 already exists, skipping initiation.');
} else {
  const config = {
    _id: 'rs0',
    members: [
      { _id: 0, host: 'mongo1:27017', priority: 2 },   // preferred primary
      { _id: 1, host: 'mongo2:27017', priority: 1 },
      { _id: 2, host: 'mongo3:27017', priority: 1 }
    ]
  };
  printjson(config);
  const r = admin.runCommand({ replSetInitiate: config });
  print(`replSetInitiate -> ok: ${r.ok}`);
}

line('Step 2  Wait for the election (up to 60 seconds)');
let ready = false;
for (let i = 0; i < 60 && !ready; i++) {
  try {
    const s = admin.runCommand({ replSetGetStatus: 1 });
    ready = s.members.some(m => m.stateStr === 'PRIMARY')
         && s.members.every(m => m.stateStr === 'PRIMARY' || m.stateStr === 'SECONDARY');
  } catch (e) { /* not ready yet */ }
  if (!ready) sleep(1000);
}
print(ready ? 'Election finished: one PRIMARY and two SECONDARY members.' : 'Still settling, run 00_status.js in a few seconds.');

line('Step 3  Members');
printMembers(admin);
