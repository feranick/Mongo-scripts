# Mongo Scripts

Small `mongosh`-based helpers for per-device maintenance of a MongoDB database.
Both scripts operate on the `device_name` field and sweep every non-system
collection in the target database; they share a single connection-config file.

- **`mongosh_dropdevice.sh`** — deletes all documents for a device.
- **`mongosh_exportdevice.sh`** — exports all documents for a device (the
  read-only counterpart of the delete script).

Each script prints its usage and version with `-h` / `--help`.

### Files

| File                      | Purpose                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `mongosh_dropdevice.sh`   | Wrapper: reads config, prompts for confirmation, runs delete  |
| `mongosh_dropdevice.js`   | mongosh script that performs the delete                        |
| `mongosh_exportdevice.sh` | Wrapper: finds matching collections and exports the documents  |
| `mongosh_db.conf`         | Connection settings (host, credentials, target DB)            |

`mongosh_exportdevice.sh` has no companion `.js`: it discovers the collections
holding the device's data with an inline `mongosh` query, then hands the actual
dump to `mongoexport`.

### Setup

Copy the example config and fill in your values:

```bash
cp mongosh_db.conf.example mongosh_db.conf
chmod 600 mongosh_db.conf   # contains the DB password in plaintext
```

Make the scripts executable:

```bash
chmod +x mongosh_dropdevice.sh mongosh_exportdevice.sh
```

### Requirements

- [`mongosh`](https://www.mongodb.com/docs/mongodb-shell/) on PATH — used by
  both scripts.
- [`mongoexport`](https://www.mongodb.com/docs/database-tools/installation/)
  on PATH — used by `mongosh_exportdevice.sh` only. It ships in the **MongoDB
  Database Tools** package, which installs separately from `mongosh`.

## mongosh_dropdevice

Deletes all documents for a single device across every non-system collection.
Collections and their indexes are kept — only matching documents are removed.

### Usage

```bash
./mongosh_dropdevice.sh <device_name>
```

Example — remove everything belonging to `pico2`:

```bash
./mongosh_dropdevice.sh pico2
```

The script asks you to re-type the device name before deleting. This is
irreversible; make sure you have a backup if needed.

## mongosh_exportdevice

Exports all documents for a single device across every non-system collection.
For each collection that contains matching documents, one file is written,
named `<device>_<collection>_<UTC-timestamp>.<csv|json>`. A device whose data
lives in a single collection therefore produces a single file.

Per-collection files are used because CSV is inherently per-collection tabular:
different collections may have different schemas.

### Usage

```bash
./mongosh_exportdevice.sh [-j|--json] <device_name> [output_dir]
```

| Argument / option | Meaning                                                        |
| ----------------- | ------------------------------------------------------------- |
| `<device_name>`   | Device to export (matched on `device_name`). Required.        |
| `[output_dir]`    | Directory for the output files (default: current directory).  |
| `-j`, `--json`    | Output JSON arrays instead of CSV.                            |
| `-h`, `--help`    | Show usage and version, then exit.                           |

Examples:

```bash
# CSV (default), written to the current directory
./mongosh_exportdevice.sh pico2

# JSON, written to a chosen directory
./mongosh_exportdevice.sh --json pico2 ./exports
```

### CSV field detection

`mongoexport` CSV mode requires an explicit field list. For each matching
collection the script auto-detects it by sampling the matching documents with
`mongosh` (union of top-level keys across up to `SAMPLE_LIMIT` documents,
default 200). Notes:

- Only **top-level** fields become columns; nested sub-documents are not
  expanded into dot-path columns.
- A field that appears only beyond the sampled documents could be missed.
  Raise `SAMPLE_LIMIT` at the top of the script (or set it to `0` to scan all
  matches) if that's a concern.
- The JSON path exports whole documents verbatim and has no such limitation.

The detected field list is printed before each export so it can be checked
against expectations, and `mongoexport` reports the record count per file.

### Notes

- `mongosh_db.conf` is git-ignored because it holds credentials. Commit
  `mongosh_db.conf.example` with placeholder values instead.
- Both scripts read the same `mongosh_db.conf`.
- To run `mongosh_dropdevice.sh` non-interactively (e.g. from cron), remove the
  confirmation block marked in the script. `mongosh_exportdevice.sh` is
  read-only and already non-interactive.
