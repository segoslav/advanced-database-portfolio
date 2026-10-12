// =====================================================================
// ShopNaija — Replica set status (run any time)
//   docker exec mongo2 mongosh --nodb --quiet --file /scripts/00_status.js
// Asks the first member that answers, so it works even when one is down.
// =====================================================================
load('/scripts/common.js');

line(`Replica set status at ${clock()}`);
let shown = false;
for (const host of HOSTS) {
  try {
    const admin = direct(host, 'admin');
    const s = printMembers(admin);
    const primary = s.members.find(m => m.stateStr === 'PRIMARY');
    print(`\nCurrent primary: ${primary ? primary.name : 'NONE (election in progress, or no majority)'}`);
    shown = true;
    break;
  } catch (e) {
    print(`${host} did not answer (${e.message.split('\n')[0]}), trying the next member...`);
  }
}
if (!shown) print('No member answered. Are the containers running?  docker compose ps');
