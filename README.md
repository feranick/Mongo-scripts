# Mongo Scripts

Small `mongosh`-based helpers for per-device maintenance of a MongoDB database.

All devices' documents live in a **single collection** (`COLLECTION_NAME` in
`mongosh_db.conf`, matching the backend's `config.cfg` — `LabMonitor`). Devices
are distinguished by the `device_name` **field**, not by separate collections.
Every script keys on that field.

- **`mongosh_dropdevice.sh`** — deletes all documents for a device.
- **`mongosh_exportdevice.sh`** — exports all documents for a device.
- **`mongosh_importdevice.sh`** — imports a JSON file into the shared collection
  (device_name is used to validate the file, not to choose a collection).
- **`mongosh_adddevice.sh`** — appends a JSON file for a device that is already
  present in the shared collection.

Each script prints its usage and version with `-h` / `--help`.

### Files

| File                      | Purpose                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `mongosh_dropdevice.sh`   | Wrapper: reads config, prompts for confirmation, runs delete  |
| `mongosh_dropdevice.js`   | mongosh script that performs the delete                        |
| `mongosh_exportdevice.sh` | Wrapper: finds matching collections and exports the documents  |
| `mongosh_importdevice.sh` | Wrapper: validates and imports a JSON file into the collection  |
| `mongosh_adddevice.sh`    | Wrapper: appends a JSON file for an existing device             |
| `mongosh_db.conf`         | Connection settings + `COLLECTION_NAME`                        |

Only `mongosh_dropdevice.sh` has a companion `.js`. The export/import/add
wrappers use inline `mongosh` queries plus the MongoDB Database Tools
(`mongoexport` / `mongoimport`) for the bulk data transfer.

### Setup

Copy the example config and fill in your values:

```bash
cp mongosh_db.conf.example mongosh_db.conf
chmod 600 mongosh_db.conf   # contains the DB password in plaintext
```

`COLLECTION_NAME` in `mongosh_db.conf` **must match** `COLLECTION_NAME` in the
server's `config.cfg`; otherwise import/add would write to the wrong collection.

Make the scripts executable:

```bash
chmod +x mongosh_dropdevice.sh mongosh_exportdevice.sh \
         mongosh_importdevice.sh mongosh_adddevice.sh
```

### Requirements

- [`mongosh`](https://www.mongodb.com/docs/mongodb-shell/) on PATH — used by
  `dropdevice`, `exportdevice`, and `adddevice`.
- [`mongoexport` / `mongoimport`](https://www.mongodb.com/docs/database-tools/installation/)
  on PATH — used by `exportdevice` (`mongoexport`) and by `importdevice` /
  `adddevice` (`mongoimport`). They ship in the **MongoDB Database Tools**
  package, which installs separately from `mongosh`.
- `jq` **or** `python3` — optional, used by `importdevice` and `adddevice` to
  validate the input file before writing. If neither is present the check is
  skipped with a warning.

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
named `<device>_<collection>_<UTC-timestamp>.<csv|json>`. With the current
single-collection backend this is normally one file per device, e.g.
`pico2_LabMonitor_<timestamp>.csv`.

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

### CSV field detection

`mongoexport` CSV mode requires an explicit field list, auto-detected by
sampling matching documents with `mongosh` (union of top-level keys across up to
`SAMPLE_LIMIT` documents, default 200). Notes:

- Only top-level fields become columns (all LabMonitor fields are flat, so this
  covers everything).
- Documents from different ingest paths differ slightly (the Pico path stores
  `mongo_url`; the browser path stores `client_submission_time`; the backend
  adds `server_submission_time` / `datetime_utc_pico` / `datetime_utc_client`).
  The union sampling captures all of these, but for a device fed by mixed
  sources set `SAMPLE_LIMIT=0` (scan all) to be certain no column is missed.
- The JSON path exports whole documents verbatim (relaxed extended JSON, so
  `_id` and datetime fields round-trip cleanly through `mongoimport`).

## mongosh_importdevice

Imports a JSON file into the shared collection (`COLLECTION_NAME`). The
`<device_name>` argument is **not** a collection name — all devices share one
collection and are distinguished by the `device_name` field. `device_name` is
used only to check that every document in the file belongs to that device before
anything is written.

### Usage

```bash
./mongosh_importdevice.sh <device_name> <data.json>
```

| Argument       | Meaning                                                            |
| -------------- | ---------------------------------------------------------------- |
| `<device_name>`| Expected `device_name` value in every document.                   |
| `<data.json>`  | Path to the JSON file to import.                                   |
| `-h`, `--help` | Show usage and version, then exit.                               |

Example — restore `pico2`'s data from a JSON export:

```bash
./mongosh_importdevice.sh pico2 pico2_LabMonitor_20260704T120000Z.json
```

## mongosh_adddevice

Appends a JSON file to the shared collection for a device that is **already
present**. This is `mongosh_importdevice.sh` plus a precondition: at least one
document with `device_name == <device_name>` must already exist in the
collection. If not, it aborts and directs you to `mongosh_importdevice.sh`.

### Usage

```bash
./mongosh_adddevice.sh <device_name> <data.json>
```

| Argument       | Meaning                                                            |
| -------------- | ---------------------------------------------------------------- |
| `<device_name>`| Device that must already exist; expected `device_name` value.      |
| `<data.json>`  | Path to the JSON file to append.                                   |
| `-h`, `--help` | Show usage and version, then exit.                               |

Before appending, it reports how many documents currently match the device.

## Input format and validation (import / add)

`mongosh_importdevice.sh` and `mongosh_adddevice.sh` share the same handling:

- The file may be a **JSON array** (as written by `mongosh_exportdevice.sh
  --json`) or **newline-delimited JSON**. The format is detected automatically
  from the first non-whitespace character.
- Before writing, every document is checked to have `device_name` equal to the
  argument (via `jq`, else `python3`, else skipped with a warning). A mismatch
  or unparseable file aborts before anything is written.
- Both write into `COLLECTION_NAME` using `mongoimport`'s default **`insert`**
  mode, so documents that already exist (same `_id`) are not overwritten; those
  rows are reported as errors and the rest still load. Add `--mode=upsert` or
  `--drop` to the invocation for replace semantics.

## Security note

The backend stores the auth token in the data. `data_collector.wsgi` validates
`mongo_secret_key` from each payload but inserts the document unmodified, so
`mongo_secret_key` (equal to the server secret) — and, for Pico-submitted
records, `mongo_url` — is saved in every document. Consequences:

- `mongosh_exportdevice.sh` will write those values into the export files. Treat
  exports as sensitive: `chmod 600` and keep them out of git.
- The cleanest fix is server-side: drop the field before insert in
  `data_collector.wsgi`, e.g. `data.pop('mongo_secret_key', None)` (and
  `mongo_url`) right after the key check.

### Notes

- `mongosh_db.conf` is git-ignored because it holds credentials. Commit
  `mongosh_db.conf.example` with placeholder values instead.
- All scripts read the same `mongosh_db.conf`.
- The scripts authenticate as a separate admin account (`authSource=admin` by
  default) rather than the app user in `config.cfg`
  (`authSource=LabMonitorDB`); make sure that admin account can read/write
  `LabMonitorDB`.
- `exportdevice` is read-only, and `importdevice` / `adddevice` are additive;
  all three run non-interactively. To run `mongosh_dropdevice.sh`
  non-interactively (e.g. from cron), remove the confirmation block marked in
  the script.
