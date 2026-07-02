// Removes ALL documents from every non-system collection in the target database.
// The collections themselves and their indexes are preserved — this uses
// deleteMany({}) (empty filter matches everything), NOT drop().
//
// The database name is read from TARGET_DB (set by the wrapper shell script,
// which sources it from mongosh_db.conf).

const targetDb = process.env.TARGET_DB;

if (!targetDb) {
  print("ERROR: TARGET_DB is not set. Aborting.");
  quit(1);
}

use(targetDb);

print("Target database: " + targetDb);
print("Clearing ALL documents from every non-system collection.");
print("-----------------------------------------");

let totalRemoved = 0;

db.getCollectionNames().forEach(function (collectionName) {
  if (!collectionName.startsWith("system.")) {
    const result = db[collectionName].deleteMany({});
    print("Removed " + result.deletedCount + " documents from collection: " + collectionName);
    totalRemoved += result.deletedCount;
  }
});

print("-----------------------------------------");
print("Done. Total documents removed: " + totalRemoved);
