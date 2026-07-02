// Removes ALL documents for a single device across every collection in LabMonitorDB.
// The device name is read from the DEVICE_NAME environment variable, which is set
// by the wrapper script (mongosh_dropdevice.sh). Passing it via the environment
// avoids the quoting/injection pitfalls of building an --eval string by hand.

const deviceName = process.env.DEVICE_NAME;

if (!deviceName) {
  print("ERROR: No device name provided (DEVICE_NAME is empty). Aborting.");
  quit(1);
}

use("LabMonitorDB");

print("Target database:    LabMonitorDB");
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
