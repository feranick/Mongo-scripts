#!/bin/bash
#
# mongosh_exportdevice.sh
#
# Exports every document whose "device_name" matches the given argument,
# across ALL collections in the target database -- the export counterpart of
# mongosh_dropdevice.sh (same argument, same cross-collection sweep, but it
# saves the data instead of deleting it).
#
#   Default output:  CSV
#   With -j/--json:  JSON (a single JSON array)
#
# One file is written per collection that contains matching documents:
#   <device>_<collection>_<UTC-timestamp>.<csv|json>
# (A device whose data lives in a single collection therefore yields one file.)
# Per-collection files are used because CSV is inherently per-collection
# tabular -- different collections can have different schemas.
#
# Connection settings are read from mongosh_db.conf (same directory) -- the
# same file already used by mongosh_dropdevice.sh / mongosh_cleardb.sh.
#
# CSV note: mongoexport's CSV mode requires an explicit --fields list. For each
# matching collection the field list is auto-detected by sampling the matching
# documents with mongosh (union of top-level keys across up to $SAMPLE_LIMIT
# matches). Consequences:
#   - Only TOP-LEVEL fields become columns; nested sub-documents are not
#     expanded into dot-path columns (fine for the flat LabMonitor sensor docs).
#   - If a rare field appears only beyond the sampled docs it could be missed.
#     Raise SAMPLE_LIMIT (or set it to 0 to scan all matches) if needed.
# The JSON path exports whole documents verbatim and has no such limitation.
#
# Tools: BOTH mongosh (to find matching collections / CSV fields) and
# mongoexport (to run the filtered export) are required, for either format.
#
# Usage: ./mongosh_exportdevice.sh [-j|--json] <device_name> [output_dir]

VERSION="2026.07.04.2"
SCRIPT_NAME="$(basename "$0")"

# How many matching documents to sample per collection when detecting CSV
# fields. 0 = scan all matches.
SAMPLE_LIMIT=200

usage() {
    echo "Usage: $SCRIPT_NAME [-j|--json] <device_name> [output_dir]"
}

show_help() {
    cat <<EOF
$SCRIPT_NAME  version $VERSION

Exports every document whose device_name matches the given argument, across all
collections in the target database, writing one file per collection that
contains matches. Default output is CSV; use -j/--json for JSON arrays.
Connection settings come from mongosh_db.conf in the same directory.

Usage: $SCRIPT_NAME [-j|--json] <device_name> [output_dir]

Arguments:
  <device_name>  Device to export (matched on the device_name field). Required.
  [output_dir]   Directory for the output files (default: current directory).
                 Files: <device>_<collection>_<UTC-timestamp>.<csv|json>

Options:
  -j, --json     Output JSON arrays instead of CSV.
  -h, --help     Show this help and version, then exit.
EOF
}

# --- Parse arguments (flag may appear anywhere) ---------------------------
FORMAT="csv"
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -j|--json)  FORMAT="json"; shift ;;
        -h|--help)  show_help; exit 0 ;;
        --)         shift; while [ "$#" -gt 0 ]; do POSITIONAL+=("$1"); shift; done ;;
        -*)         echo "ERROR: Unknown option: $1"; usage; exit 1 ;;
        *)          POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ -z "${1:-}" ]; then
    echo "ERROR: Missing required argument."
    usage
    exit 1
fi
DEVICE_NAME="$1"
OUTPUT_DIR="${2:-.}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: Output directory does not exist: $OUTPUT_DIR"
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

# --- Tool availability ----------------------------------------------------
if ! command -v mongosh >/dev/null 2>&1; then
    echo "ERROR: 'mongosh' not found on PATH (needed to locate matching collections)."
    exit 1
fi
if ! command -v mongoexport >/dev/null 2>&1; then
    echo "ERROR: 'mongoexport' not found on PATH."
    echo "It ships in the MongoDB Database Tools package (separate from mongosh):"
    echo "  https://www.mongodb.com/docs/database-tools/installation/"
    exit 1
fi

URI="mongodb://${MONGO_HOST}/${TARGET_DB}?authSource=${AUTH_DB}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

# device_name matching inside mongosh uses process.env (injection-safe, same as
# mongosh_dropdevice.js). For mongoexport --query we must build a JSON string on
# the command line, so escape backslashes then double-quotes in the device name.
_dev_esc=${DEVICE_NAME//\\/\\\\}
_dev_esc=${_dev_esc//\"/\\\"}
QUERY="{\"device_name\":\"${_dev_esc}\"}"

# Sanitize the device name for use in filenames (leave the query value intact).
SAFE_DEV="$(printf '%s' "$DEVICE_NAME" | tr ' /\\' '___')"

echo "Connecting to MongoDB as user: $ADMIN_USER"
echo "Exporting device_name == \"$DEVICE_NAME\" from ${TARGET_DB} on ${MONGO_HOST}"
echo "Format: ${FORMAT}    Output dir: ${OUTPUT_DIR}"
echo "-----------------------------------------"
echo "Scanning collections for matches..."

# For each non-system collection with >=1 matching doc, print:
#   <collection>\t<comma-separated top-level fields among matching docs>
DETECT="$(DEVICE_NAME="$DEVICE_NAME" LIMIT="$SAMPLE_LIMIT" mongosh "$URI" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASS" \
    --quiet \
    --eval '
        const dev = process.env.DEVICE_NAME;
        const limit = parseInt(process.env.LIMIT, 10) || 0;
        const q = { device_name: dev };
        db.getCollectionNames().forEach(function (c) {
            if (c.startsWith("system.")) return;
            const coll = db.getCollection(c);
            if (coll.countDocuments(q) === 0) return;
            const keys = new Set();
            let cur = coll.find(q);
            if (limit > 0) { cur = cur.limit(limit); }
            cur.forEach(function (doc) {
                Object.keys(doc).forEach(function (k) { keys.add(k); });
            });
            print(c + "\t" + [...keys].join(","));
        });
    ')"

if [ -z "$DETECT" ]; then
    echo "No documents found with device_name == \"$DEVICE_NAME\" in any collection."
    exit 1
fi

TOTAL_FILES=0
FAILED=0
while IFS=$'\t' read -r COLL FIELDS; do
    [ -z "$COLL" ] && continue
    OUTPUT_FILE="${OUTPUT_DIR%/}/${SAFE_DEV}_${COLL}_${TS}.${FORMAT}"
    echo "-----------------------------------------"
    echo "Collection: $COLL"
    echo "Writing:    $OUTPUT_FILE"

    if [ "$FORMAT" = "json" ]; then
        if mongoexport "$URI" \
            -u "$ADMIN_USER" \
            -p "$ADMIN_PASS" \
            --collection "$COLL" \
            --query "$QUERY" \
            --jsonArray \
            --out "$OUTPUT_FILE"; then
            TOTAL_FILES=$((TOTAL_FILES + 1))
        else
            echo "  -> Export FAILED for collection $COLL"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "Fields:     $FIELDS"
        if mongoexport "$URI" \
            -u "$ADMIN_USER" \
            -p "$ADMIN_PASS" \
            --collection "$COLL" \
            --query "$QUERY" \
            --type=csv \
            --fields="$FIELDS" \
            --out "$OUTPUT_FILE"; then
            TOTAL_FILES=$((TOTAL_FILES + 1))
        else
            echo "  -> Export FAILED for collection $COLL"
            FAILED=$((FAILED + 1))
        fi
    fi
done <<< "$DETECT"

echo "-----------------------------------------"
echo "Done. Files written: $TOTAL_FILES    Failures: $FAILED"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
