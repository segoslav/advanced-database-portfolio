// =====================================================================
// Shared helpers, loaded by every Portfolio 5 script with load().
// =====================================================================

// Connection string for the whole replica set. The driver discovers which
// member is primary and automatically follows it after a failover.
const RS_URI = 'mongodb://mongo1:27017,mongo2:27017,mongo3:27017/shopnaija'
             + '?replicaSet=rs0&serverSelectionTimeoutMS=20000';

const HOSTS = ['mongo1:27017', 'mongo2:27017', 'mongo3:27017'];

function line(title) {
  print(`\n==================================================================\n${title}\n==================================================================`);
}

// Connect to ONE specific member, bypassing replica-set routing,
// so we can see exactly what that server holds.
function direct(host, dbName) {
  return connect(`mongodb://${host}/${dbName || 'shopnaija'}`
               + '?directConnection=true&readPreference=secondaryPreferred&serverSelectionTimeoutMS=3000');
}

// Ask a member for the replica-set status and print one line per member.
function printMembers(adminDb) {
  const s = adminDb.runCommand({ replSetGetStatus: 1 });
  print(`Replica set "${s.set}", as seen by this member:`);
  print('member          state       health  last write applied');
  s.members.forEach(m => {
    const applied = m.optimeDate ? m.optimeDate.toISOString().replace('T', ' ').substring(0, 19) : '-';
    print(`${m.name.padEnd(15)} ${String(m.stateStr).padEnd(11)} ${String(m.health).padEnd(7)} ${applied}${m.self ? '   <- this member' : ''}`);
  });
  return s;
}

const clock = () => new Date().toISOString().substring(11, 19);
