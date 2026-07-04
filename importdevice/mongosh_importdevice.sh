#!/bin/bash
#
# mongosh_importdevice.sh
#
# Imports a JSON file into the collection named after the given device -- the
# inverse of mongosh_exportdevice.sh. The first argument is used both as the
# TARGET COLLECTION name and as the expected value of the device_name field in
# every document.
#
# The input file may be:
#   - a JSON array   (as written by mongosh_exportdevice.sh --json), or
#   - newline-delimited JSON (one object per line).
# The format is auto-detected from the first non-whitespace character.
#
# Before importing, every document is checked to have device_name equal to the
# <device_name> argument (the import-side analog of dropdevice's confirmation).
# This uses jq if present, otherwise python3; if neither is available the check
# is skipped with a warning. A mismatch (or unparseable file) aborts the import.
#
# Import uses mongoimport's default "insert" mode, so documents that already
# exist (same _id) are NOT overwritten -- those rows are reported as errors by
# mongoimport and the rest still import. Use --mode=upsert or --drop manually if
# you want different behaviour.
#
# Connection settings are read from mongosh_db.conf (same directory) -- the same
# file used by the drop/export scripts.
#
# Tools: mongoimport (MongoDB Database Tools) is required; jq OR python3 is used
# for validation if available.
#
# Usage: ./mongosh_importdevice.sh <device_name> <data.json>

VERSION="2026.07.04.1"
SCRIPT_NAME="$(basename "$0")"

usage() {
    echo "Usage: $SCRIPT_NAME <device_name> <data.json>"
}

show_help() {
    cat <<EOF
$SCRIPT_NAME  version $VERSION

Imports a JSON file into the collection named after the given device (the
inverse of mongosh_exportdevice.sh). The file may be a JSON array (as written
by mongosh_exportdevice.sh --json) or newline-delimited JSON; the format is
detected automatically. Before importing, every document is checked to have
device_name == <device_name> (uses jq or python3; skipped with a warning if
neither is present). Connection settings come from mongosh_db.conf in the same
directory.

Usage: $SCRIPT_NAME <device_name> <data.json>

Arguments:
  <device_name>  Target collection name, and the expected device_name value in
                 every document. Required.
  <data.json>    Path to the JSON file to import. Required.

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

# Refuse to touch reserved collections.
case "$DEVICE_NAME" in
    system.*)
        echo "ERROR: refusing to import into a reserved 'system.*' collection."
        exit 1 ;;
esac

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

if ! command -v mongoimport >/dev/null 2>&1; then
    echo "ERROR: 'mongoimport' not found on PATH."
    echo "It ships in the MongoDB Database Tools package (separate from mongosh):"
    echo "  https://www.mongodb.com/docs/database-tools/installation/"
    exit 1
fi

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

echo "Connecting to MongoDB as user: $ADMIN_USER"
echo "Importing '$DATA_FILE' (format: $FMT)"
echo "into collection \"$DEVICE_NAME\" in ${TARGET_DB} on ${MONGO_HOST}"
echo "-----------------------------------------"
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

URI="mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}"

IMPORT_ARGS=(--collection "$DEVICE_NAME" --file "$DATA_FILE")
[ "$FMT" = "array" ] && IMPORT_ARGS+=(--jsonArray)

if mongoimport "$URI" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    "${IMPORT_ARGS[@]}"; then
    echo "-----------------------------------------"
    echo "Import completed."
else
    echo "-----------------------------------------"
    echo "Error importing data."
    exit 1
fi
