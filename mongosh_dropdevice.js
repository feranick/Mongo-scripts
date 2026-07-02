// Removes ALL documents for a single device across every collection in the target DB.
// Values are read from environment variables set by the wrapper script
// (mongosh_dropdevice.sh), which sources them from mongosh_db.conf:
//   DEVICE_NAME  the device to purge
//   TARGET_DB    the database to operate on
// Passing them via the environment avoids the quoting/injection pitfalls of
// hand-building an --eval string.

const deviceName = process.env.DEVICE_NAME;
const targetDb = process.env.TARGET_DB;

if (!deviceName) {
  print("ERROR: No device name provided (DEVICE_NAME is empty). Aborting.");
  quit(1);
}
if (!targetDb) {
  print("ERROR: TARGET_DB is not set. Aborting.");
  quit(1);
}

use(targetDb);

print("Target database:    " + targetDb);
print("Target device_name: " + deviceName);
print("-----------------------------------------");

let totalRemoved = 0;

db.getCollectionNames().forEach(function (collectionName) {
  if (!collectionName.startsWith("system.")) {
    const result = db[collectionName].deleteMany({ "device_name": deviceName });
    if (result.deletedCount > 0) {
      print("Removed " + result.deletedCount + " documents from collection: " + collectionName);
      totalRemoved += result.deletedCount;
    }
  }
});

print("-----------------------------------------");
print("Done. Total documents removed: " + totalRemoved);
