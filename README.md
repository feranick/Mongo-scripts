# Mongo Scripts
## mongosh-dropdevice

Small mongosh helper that deletes all documents for a single device across
every non-system collection in a MongoDB database. Collections and their
indexes are kept — only matching documents are removed.

### Files

| File                    | Purpose                                             |
| ----------------------- | --------------------------------------------------- |
| `mongosh_dropdevice.sh` | Wrapper: reads config, prompts for confirmation     |
| `mongosh_dropdevice.js` | mongosh script that runs the delete                 |
| `mongosh_db.conf`       | Connection settings (host, credentials, target DB)  |

### Setup

Copy the example config and fill in your values:

```bash
cp mongosh_db.conf.example mongosh_db.conf
chmod 600 mongosh_db.conf   # contains the DB password in plaintext
```

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

### Notes

- `mongosh_db.conf` is git-ignored because it holds credentials. Commit
  `mongosh_db.conf.example` with placeholder values instead.
- To run non-interactively (e.g. from cron), remove the confirmation block
  marked in `mongosh_dropdevice.sh`.
- Requires [`mongosh`](https://www.mongodb.com/docs/mongodb-shell/) on PATH.
