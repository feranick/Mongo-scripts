# Mongo Scripts

Small `mongosh`-based helpers for per-device maintenance of a MongoDB database.
The scripts operate on the `device_name` field (which, by convention here, also
names the per-device collection) and share a single connection-config file.

- **`mongosh_dropdevice.sh`** — deletes all documents for a device.
- **`mongosh_exportdevice.sh`** — exports all documents for a device.
- **`mongosh_importdevice.sh`** — imports a JSON file back into a device's
  collection (the inverse of export).

Each script prints its usage and version with `-h` / `--help`.

### Files

| File                      | Purpose                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `mongosh_dropdevice.sh`   | Wrapper: reads config, prompts for confirmation, runs delete  |
| `mongosh_dropdevice.js`   | mongosh script that performs the delete                        |
| `mongosh_exportdevice.sh` | Wrapper: finds matching collections and exports the documents  |
| `mongosh_importdevice.sh` | Wrapper: validates and imports a JSON file into a collection    |
| `mongosh_db.conf`         | Connection settings (host, credentials, target DB)            |

Only `mongosh_dropdevice.sh` has a companion `.js`. The export and import
wrappers use inline `mongosh` queries plus the MongoDB Database Tools
(`mongoexport` / `mongoimport`) for the bulk data transfer.

### Setup

Copy the example config and fill in your values:

```bash
cp mongosh_db.conf.example mongosh_db.conf
chmod 600 mongosh_db.conf   # contains the DB password in plaintext
```

Make the scripts executable:

```bash
chmod +x mongosh_dropdevice.sh mongosh_exportdevice.sh mongosh_importdevice.sh
```

### Requirements

- [`mongosh`](https://www.mongodb.com/docs/mongodb-shell/) on PATH — used by
  `dropdevice` and `exportdevice`.
- [`mongoexport` / `mongoimport`](https://www.mongodb.com/docs/database-tools/installation/)
  on PATH — used by `exportdevice` and `importdevice` respectively. They ship in
  the **MongoDB Database Tools** package, which installs separately from
  `mongosh`.
- `jq` **or** `python3` — optional, used by `importdevice` to validate the input
  file before writing. If neither is present the check is skipped with a warning.

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

## mongosh_importdevice

Imports a JSON file into the collection named after the given device — the
inverse of `mongosh_exportdevice.sh`. The first argument is used both as the
target collection name and as the expected `device_name` value in every
document.

### Usage

```bash
./mongosh_importdevice.sh <device_name> <data.json>
```

| Argument       | Meaning                                                            |
| -------------- | ---------------------------------------------------------------- |
| `<device_name>`| Target collection name, and the expected `device_name` value.     |
| `<data.json>`  | Path to the JSON file to import.                                   |
| `-h`, `--help` | Show usage and version, then exit.                               |

Example — restore `pico2`'s data from a JSON export:

```bash
./mongosh_importdevice.sh pico2 pico2_pico2_20260704T120000Z.json
```

### Input format and validation

- The file may be a **JSON array** (as written by `mongosh_exportdevice.sh
  --json`) or **newline-delimited JSON** (one object per line). The format is
  detected automatically from the first non-whitespace character.
- Before importing, every document is checked to have `device_name` equal to the
  `<device_name>` argument. This uses `jq` if available, otherwise `python3`; if
  neither is present the check is skipped with a warning. A mismatch — or an
  unparseable file — aborts the import before anything is written.
- Import uses `mongoimport`'s default **`insert`** mode, so documents that
  already exist (same `_id`) are not overwritten; those rows are reported as
  errors by `mongoimport` and the rest still import. Edit the invocation to add
  `--mode=upsert` or `--drop` if you want replace semantics.
- The script refuses to import into a reserved `system.*` collection.

Because the target collection defaults to the device name, this round-trips
cleanly for devices whose data lives in a single collection. If you import a
file that came from a different source collection, target the correct
collection by naming it in the first argument.

### Notes

- `mongosh_db.conf` is git-ignored because it holds credentials. Commit
  `mongosh_db.conf.example` with placeholder values instead.
- All three scripts read the same `mongosh_db.conf`.
- `mongosh_exportdevice.sh` and `mongosh_importdevice.sh` are read-safe and
  additive respectively, and both run non-interactively. To run
  `mongosh_dropdevice.sh` non-interactively (e.g. from cron), remove the
  confirmation block marked in the script.
