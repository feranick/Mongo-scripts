#!/bin/bash
#
# Clears ALL documents from every non-system collection in the target database.
# The collections and their indexes are kept (uses deleteMany({}), not drop()).
#
# Connection settings are read from mongosh_db.conf (same directory).
#
# Usage: ./mongosh_cleardb.sh

# Resolve paths relative to this script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mongosh_db.conf"
JS_SCRIPT="${SCRIPT_DIR}/mongosh_cleardb.js"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

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

if TARGET_DB="$TARGET_DB" mongosh "mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --file "$JS_SCRIPT"; then
    echo "MongoDB script executed successfully."
else
    echo "Error executing MongoDB script."
    exit 1
fi
