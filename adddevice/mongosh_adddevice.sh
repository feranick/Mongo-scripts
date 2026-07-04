#!/bin/bash
#
# mongosh_adddevice.sh
#
# Appends the documents in a JSON file to the shared LabMonitor collection, for
# a device that is ALREADY present. This is mongosh_importdevice.sh plus one
# precondition: the collection (COLLECTION_NAME in mongosh_db.conf) must already
# contain at least one document with device_name == <device_name>. If it does
# not, the script aborts and points you at mongosh_importdevice.sh (use that to
# add a device for the first time).
#
# All devices share ONE collection; devices are distinguished by the
# device_name FIELD, not by collection. The <device_name> argument is used to
# (a) confirm the device already exists and (b) validate that every document in
# the file belongs to that device. The write target is always COLLECTION_NAME.
#
# The input file may be a JSON array (as written by mongosh_exportdevice.sh
# --json) or newline-delimited JSON; the format is auto-detected. Append uses
# mongoimport's default "insert" mode (existing _id values are not overwritten).
#
# Connection settings are read from mongosh_db.conf (same directory).
#
# Tools: mongosh (existence check) and mongoimport (append) are required;
# jq OR python3 is used for validation if available.
#
# Usage: ./mongosh_adddevice.sh <device_name> <data.json>

VERSION="2026.07.04.2"
SCRIPT_NAME="$(basename "$0")"

usage() {
    echo "Usage: $SCRIPT_NAME <device_name> <data.json>"
}

show_help() {
    cat <<EOF
$SCRIPT_NAME  version $VERSION

Appends a JSON file to the shared collection (COLLECTION_NAME in
mongosh_db.conf) for a device that already exists there. This is
mongosh_importdevice.sh plus a precondition: at least one document with
device_name == <device_name> must already be present; if not, use
mongosh_importdevice.sh to add the device for the first time. All devices share
one collection and are distinguished by the device_name field. The file may be a
JSON array (as written by mongosh_exportdevice.sh --json) or newline-delimited
JSON; the format is detected automatically. Validation uses jq or python3
(skipped with a warning if neither is present).

Usage: $SCRIPT_NAME <device_name> <data.json>

Arguments:
  <device_name>  Device that must already exist; also the expected device_name
                 value in every document. Required.
  <data.json>    Path to the JSON file to append. Required.

Options:
  -h, --help     Show this help and version, then exit.
EOF
}

# --- Parse arguments (flag may appear anywhere) ---------------------------
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)  show_help; exit 0 ;;
        --)         shift; while [ "$#" -gt 0 ]; do POSITIONAL+=("$1"); shift; done ;;
        -*)         echo "ERROR: Unknown option: $1"; usage; exit 1 ;;
        *)          POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "ERROR: Both <device_name> and <data.json> are required."
    usage
    exit 1
fi
DEVICE_NAME="$1"
DATA_FILE="$2"

if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Input file not found: $DATA_FILE"
    exit 1
fi

# Resolve paths relative to this script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mongosh_db.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [ -z "${COLLECTION_NAME:-}" ]; then
    echo "ERROR: COLLECTION_NAME is not set in mongosh_db.conf."
    echo 'Add e.g.  COLLECTION_NAME="LabMonitor"  (must match config.cfg on the server).'
    exit 1
fi
case "$COLLECTION_NAME" in
    system.*)
        echo "ERROR: refusing to write to reserved collection '$COLLECTION_NAME'."
        exit 1 ;;
esac

if ! command -v mongosh >/dev/null 2>&1; then
    echo "ERROR: 'mongosh' not found on PATH (needed to check the device exists)."
    exit 1
fi
if ! command -v mongoimport >/dev/null 2>&1; then
    echo "ERROR: 'mongoimport' not found on PATH."
    echo "It ships in the MongoDB Database Tools package (separate from mongosh):"
    echo "  https://www.mongodb.com/docs/database-tools/installation/"
    exit 1
fi

URI="mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}"

# --- Precondition: the device must already exist in the shared collection --
echo "Connecting to MongoDB as user: $ADMIN_USER"
echo "Checking that device \"$DEVICE_NAME\" already exists in collection"
echo "\"$COLLECTION_NAME\" (${TARGET_DB} on ${MONGO_HOST})..."
STATUS="$(DEVICE_NAME="$DEVICE_NAME" COLLNAME="$COLLECTION_NAME" mongosh "$URI" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --eval '
        const dev = process.env.DEVICE_NAME;
        const coll = process.env.COLLNAME;
        if (!db.getCollectionNames().includes(coll)) {
            print("NOCOLL");
        } else {
            const n = db.getCollection(coll).countDocuments({ device_name: dev });
            print(n > 0 ? "EXISTS:" + n : "ABSENT");
        }
    ')"

case "$STATUS" in
    NOCOLL)
        echo "ERROR: collection \"$COLLECTION_NAME\" does not exist in ${TARGET_DB}."
        echo "Check COLLECTION_NAME in mongosh_db.conf against the server's config.cfg."
        exit 1 ;;
    ABSENT)
        echo "ERROR: device \"$DEVICE_NAME\" is not present in \"$COLLECTION_NAME\" yet."
        echo "Use mongosh_importdevice.sh to add this device for the first time."
        exit 1 ;;
    EXISTS:*)
        echo "Device exists (${STATUS#EXISTS:} document(s) currently match device_name)." ;;
    *)
        echo "ERROR: could not determine whether the device exists."
        echo "mongosh returned: ${STATUS:-<empty>}"
        exit 1 ;;
esac

# --- Detect input format from the first non-whitespace character ----------
FIRST_CHAR="$(tr -d '[:space:]' < "$DATA_FILE" | head -c1)"
case "$FIRST_CHAR" in
    "[") FMT="array" ;;
    "{") FMT="jsonl" ;;
    *)
        echo "ERROR: '$DATA_FILE' does not look like JSON (starts with '${FIRST_CHAR}')."
        exit 1 ;;
esac

# --- Validate that every document belongs to this device ------------------
# Returns: 0 = all match, 1 = mismatch/parse error, 3 = no validator available.
validate_device() {
    if command -v jq >/dev/null 2>&1; then
        if [ "$FMT" = "array" ]; then
            jq -e --arg d "$DEVICE_NAME" 'all(.[]; .device_name == $d)' "$DATA_FILE" >/dev/null 2>&1
        else
            jq -e --arg d "$DEVICE_NAME" -s 'all(.[]; .device_name == $d)' "$DATA_FILE" >/dev/null 2>&1
        fi
        return $?
    elif command -v python3 >/dev/null 2>&1; then
        DEVICE_NAME="$DEVICE_NAME" FMT="$FMT" python3 -c '
import json, os, sys
dev = os.environ["DEVICE_NAME"]
fmt = os.environ.get("FMT", "array")
path = sys.argv[1]
try:
    if fmt == "array":
        with open(path) as f:
            docs = json.load(f)
        if not isinstance(docs, list):
            docs = [docs]
    else:
        docs = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    docs.append(json.loads(line))
except Exception as e:
    sys.stderr.write("  parse error: %s\n" % e)
    sys.exit(1)
mismatch = sum(1 for d in docs if not (isinstance(d, dict) and d.get("device_name") == dev))
sys.stderr.write("  checked %d document(s), %d mismatch(es)\n" % (len(docs), mismatch))
sys.exit(1 if mismatch else 0)
' "$DATA_FILE"
        return $?
    else
        return 3
    fi
}

echo "-----------------------------------------"
echo "Appending '$DATA_FILE' (format: $FMT) to collection \"$COLLECTION_NAME\""
echo "Validating device_name on every document..."

validate_device
case "$?" in
    0) echo "Validation passed: all documents have device_name == \"$DEVICE_NAME\"." ;;
    1) echo "ERROR: validation failed. The file did not pass the device_name"
       echo "check (mismatch or unparseable). Aborting without importing."
       exit 1 ;;
    3) echo "WARNING: neither jq nor python3 found; skipping device_name validation." ;;
esac

echo "-----------------------------------------"

IMPORT_ARGS=(--collection "$COLLECTION_NAME" --file "$DATA_FILE")
[ "$FMT" = "array" ] && IMPORT_ARGS+=(--jsonArray)

if mongoimport "$URI" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    "${IMPORT_ARGS[@]}"; then
    echo "-----------------------------------------"
    echo "Append completed."
else
    echo "-----------------------------------------"
    echo "Error appending data."
    exit 1
fi
