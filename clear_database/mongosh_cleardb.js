use("LabMonitorDB");

//const deviceName = process.argv[2]
const deviceName = "pico2"

db.getCollectionNames().forEach(function(collectionName) {    if (!collectionName.startsWith('system.')) {  var result = db[collectionName].deleteMany({ "device_name" : deviceName }); if (result.deletedCount > 0) { print("Removed " + result.deletedCount + " documents from collection: " + collectionName); }} });
