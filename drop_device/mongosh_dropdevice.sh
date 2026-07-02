#!/bin/bash
#
# Deletes every document whose "device_name" matches the given argument,
# across all collections in LabMonitorDB.
#
# Usage: ./mongosh_dropdevice.sh <device_name>

if [ -z "${1:-}" ]; then
    echo "ERROR: Missing required argument."
    echo "Usage: $0 <device_name>"
    exit 1
fi

DEVICE_NAME="$1"

MONGO_HOST="localhost:27017"
ADMIN_USER="admin"
ADMIN_PASS="password"
AUTH_DB="admin"

# Resolve the JS script next to this shell script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS_SCRIPT="${SCRIPT_DIR}/mongosh_dropdevice.js"

if [ ! -f "$JS_SCRIPT" ]; then
    echo "ERROR: Cannot find JS script at $JS_SCRIPT"
    exit 1
fi

# --- Safety confirmation (delete this block if you need non-interactive runs) ---
echo "About to remove ALL documents where device_name == \"$DEVICE_NAME\""
echo "from every collection in LabMonitorDB on $MONGO_HOST. This is irreversible."
read -r -p "Re-type the device name to confirm: " CONFIRM
if [ "$CONFIRM" != "$DEVICE_NAME" ]; then
    echo "Confirmation did not match. Aborting."
    exit 1
fi
# --------------------------------------------------------------------------------

echo "Connecting to MongoDB as user: $ADMIN_USER"

# DEVICE_NAME is exported inline so the JS script can read process.env.DEVICE_NAME.
if DEVICE_NAME="$DEVICE_NAME" mongosh "mongodb://${MONGO_HOST}/LabMonitorDB?authSource=${AUTH_DB}" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --file "$JS_SCRIPT"; then
    echo "MongoDB script executed successfully."
else
    echo "Error executing MongoDB script."
    exit 1
fi
