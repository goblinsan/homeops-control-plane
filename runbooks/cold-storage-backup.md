# Runbook: Cold Storage Backup and Restore

> **Security note:** This runbook contains no real S3 bucket names, hostnames, or credentials. All backup destinations live in `.inventory/backups.yaml` (encrypted, gitignored).

---

## Overview

This runbook describes the strategy and procedures for cold-storage backups including:

- Full filesystem backups to S3 (encrypted)
- Backup verification
- Restore from cold storage
- Retention and lifecycle policies

---

## Backup strategy

| Tier         | Storage        | Frequency    | Retention | Encryption        |
|--------------|----------------|--------------|-----------|-------------------|
| Hot backup   | Local disk     | Continuous   | 7 days    | LUKS/filesystem   |
| Warm backup  | S3             | Daily        | 30 days   | age + SSE-KMS     |
| Cold backup  | S3 Glacier     | Weekly       | 1 year    | age + SSE-KMS     |
| Offsite cold | External drive | Monthly      | Permanent | LUKS              |

Backup job definitions and S3 destinations are stored in `.inventory/backups.yaml`.

---

## Pre-backup checklist

- [ ] Confirm the source node and data directory are correct (check `.inventory/nodes.yaml`)
- [ ] Confirm the backup destination URI from `.inventory/backups.yaml`
- [ ] Ensure sufficient destination storage capacity
- [ ] Verify age encryption recipient key is available
- [ ] Optionally quiesce applications writing to the source directory

---

## Full directory backup to S3 (encrypted)

```bash
# Variables — load from inventory or set manually
SOURCE_DIR="<SOURCE_PATH>"          # e.g., /srv/data
BACKUP_NAME="<NODE_NAME>-$(date +%Y%m%d).tar"
AGE_RECIPIENT="<AGE_PUBLIC_KEY>"    # from recipient.txt
S3_URI="s3://<BUCKET>/<PREFIX>/"    # from .inventory/backups.yaml

# Create tar archive
tar cf "/tmp/${BACKUP_NAME}" -C "$(dirname "${SOURCE_DIR}")" "$(basename "${SOURCE_DIR}")"

# Encrypt with age
age --encrypt \
    --recipient "${AGE_RECIPIENT}" \
    --output "/tmp/${BACKUP_NAME}.age" \
    "/tmp/${BACKUP_NAME}"

# Upload to S3
aws s3 cp "/tmp/${BACKUP_NAME}.age" "${S3_URI}${BACKUP_NAME}.age"

# Clean up local temporary files
rm "/tmp/${BACKUP_NAME}" "/tmp/${BACKUP_NAME}.age"
```

> ⚠️ Do not leave unencrypted archives in `/tmp` longer than necessary.

---

## Backup verification

After uploading, verify the backup is readable and decryptable:

```bash
AGE_KEY_FILE="${HOMEOPS_AGE_KEY_FILE:-${HOME}/.config/homeops/identity.age}"
S3_URI="s3://<BUCKET>/<PREFIX>/<BACKUP_FILE>.age"

# Download
aws s3 cp "${S3_URI}" "/tmp/verify-backup.tar.age"

# Decrypt
age --decrypt \
    --identity "${AGE_KEY_FILE}" \
    --output "/tmp/verify-backup.tar" \
    "/tmp/verify-backup.tar.age"

# List contents (do not extract unless restoring)
tar tf "/tmp/verify-backup.tar" | head -20

# Clean up
rm "/tmp/verify-backup.tar.age" "/tmp/verify-backup.tar"
```

---

## Restore from cold storage

> ⚠️ **Restore is potentially destructive.** Restoring to a non-empty directory may overwrite existing data. Confirm the target path before running any extract command.

### 1. Fetch the backup

```bash
AGE_KEY_FILE="${HOMEOPS_AGE_KEY_FILE:-${HOME}/.config/homeops/identity.age}"
S3_URI="s3://<BUCKET>/<PREFIX>/<BACKUP_FILE>.age"
RESTORE_DIR="<RESTORE_TARGET_PATH>"

# Download
aws s3 cp "${S3_URI}" "/tmp/restore.tar.age"

# Decrypt
age --decrypt \
    --identity "${AGE_KEY_FILE}" \
    --output "/tmp/restore.tar" \
    "/tmp/restore.tar.age"
```

### 2. Verify contents before extracting

```bash
tar tf "/tmp/restore.tar"
```

### 3. Extract to restore location

```bash
# Create the restore target if needed
mkdir -p "${RESTORE_DIR}"

# --- DESTRUCTIVE: this overwrites files in RESTORE_DIR ---
# Confirm you have reviewed the tar listing above before running:
read -r -p "Type YES to extract to ${RESTORE_DIR}: " confirm
if [[ "${confirm}" == "YES" ]]; then
  tar xf "/tmp/restore.tar" -C "${RESTORE_DIR}"
  echo "Restore complete."
else
  echo "Restore cancelled."
fi
```

### 4. Clean up

```bash
rm "/tmp/restore.tar.age" "/tmp/restore.tar"
```

---

## S3 Glacier restore (cold tier)

Objects in Glacier must be restored to S3 Standard before downloading:

```bash
# Initiate a restore (retrieval takes hours for Glacier, minutes for Glacier Instant)
aws s3api restore-object \
  --bucket "<BUCKET>" \
  --key "<PREFIX>/<BACKUP_FILE>.age" \
  --restore-request '{"Days":2,"GlacierJobParameters":{"Tier":"Standard"}}'

# Check restore status (look for 'ongoing-request="false"')
aws s3api head-object \
  --bucket "<BUCKET>" \
  --key "<PREFIX>/<BACKUP_FILE>.age"
```

Once restored, download using the standard fetch procedure above.

---

## S3 lifecycle policy recommendations

Configure S3 lifecycle rules (outside this repo — reference only):

1. Transition objects to **S3 Standard-IA** after 30 days
2. Transition to **S3 Glacier Instant Retrieval** after 90 days
3. Expire objects after 365 days (adjust per retention requirements)
4. Enable **S3 Versioning** to protect against accidental overwrites

---

## Post-restore validation

- [ ] Verify file ownership and permissions match expected values
- [ ] Run application-level integrity checks (e.g., checksums, database consistency)
- [ ] Confirm services that depend on restored data start successfully
- [ ] Update `.inventory/backups.yaml` with the restore event timestamp
