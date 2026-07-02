#!/bin/bash
#
# Deletes every document whose "device_name" matches the given argument,
# across all non-system collections in the target database. The collections
# themselves are kept (uses deleteMany({ device_name: ... }), not drop()).
#
# Connection settings are read from mongosh_db.conf (same directory).
#
# Usage: ./mongosh_cleardb.sh <device_name>

if [ -z "${1:-}" ]; then
    echo "ERROR: Missing required argument."
    echo "Usage: $0 <device_name>"
    exit 1
fi

DEVICE_NAME="$1"

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
echo "About to remove ALL documents where device_name == \"$DEVICE_NAME\""
echo "from every collection in ${TARGET_DB} on ${MONGO_HOST}. This is irreversible."
read -r -p "Re-type the device name to confirm: " CONFIRM
if [ "$CONFIRM" != "$DEVICE_NAME" ]; then
    echo "Confirmation did not match. Aborting."
    exit 1
fi
# --------------------------------------------------------------------------------

echo "Connecting to MongoDB as user: $ADMIN_USER"

# DEVICE_NAME and TARGET_DB are exported inline so the JS script can read them.
if DEVICE_NAME="$DEVICE_NAME" TARGET_DB="$TARGET_DB" mongosh "mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --file "$JS_SCRIPT"; then
    echo "MongoDB script executed successfully."
else
    echo "Error executing MongoDB script."
    exit 1
fi
