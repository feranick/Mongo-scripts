#!/bin/bash
#
# Clears ALL documents from every non-system collection in LabMonitorDB.
# The collections and their indexes are kept (uses deleteMany({}), not drop()).
#
# Usage: ./mongosh_cleardb.sh

MONGO_HOST="localhost:27017"
ADMIN_USER="admin"
ADMIN_PASS="password"
AUTH_DB="admin"
TARGET_DB="LabMonitorDB"

# Resolve the JS script next to this shell script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS_SCRIPT="${SCRIPT_DIR}/mongosh_cleardb.js"

if [ ! -f "$JS_SCRIPT" ]; then
    echo "ERROR: Cannot find JS script at $JS_SCRIPT"
    exit 1
fi

# --- Safety confirmation (delete this block if you need non-interactive runs) ---
echo "About to remove ALL documents from EVERY collection in ${TARGET_DB} on ${MONGO_HOST}."
echo "Collections are kept, but every document (all devices) will be deleted. This is irreversible."
read -r -p "Type the database name (${TARGET_DB}) to confirm: " CONFIRM
if [ "$CONFIRM" != "$TARGET_DB" ]; then
    echo "Confirmation did not match. Aborting."
    exit 1
fi
# --------------------------------------------------------------------------------

echo "Connecting to MongoDB as user: $ADMIN_USER"

if mongosh "mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --file "$JS_SCRIPT"; then
    echo "MongoDB script executed successfully."
else
    echo "Error executing MongoDB script."
    exit 1
fi
