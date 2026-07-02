// Removes ALL documents from every non-system collection in LabMonitorDB.
// The collections themselves and their indexes are preserved — this uses
// deleteMany({}) (empty filter matches everything), NOT drop().

use("LabMonitorDB");

print("Target database: LabMonitorDB");
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
