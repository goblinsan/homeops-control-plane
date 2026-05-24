# Runbook: Secure Inventory Management

> **Security note:** This runbook documents the encrypted inventory workflow. No real bucket names, key IDs, or credentials are stored here.

---

## Overview

The HomeOps inventory is an encrypted bundle stored in S3. It contains:

```
.inventory/
  nodes.yaml      – physical and virtual nodes
  repos.yaml      – managed Git repositories
  services.yaml   – service-to-host mappings
  backups.yaml    – backup job definitions and destinations
```

The bundle is encrypted client-side with [age](https://github.com/FiloSottile/age) before being uploaded to S3. The GitHub repository never contains decrypted inventory data.

---

## Encryption model

```
Local plaintext (.inventory/)
        │
        ▼  age --encrypt --recipient <AGE_PUBLIC_KEY>
        │
homeops-inventory.tar.age
        │
        ▼  aws s3 cp
        │
S3 (encrypted at rest)
```

- **age** provides client-side encryption using the age public key
- **S3 SSE-KMS** (optional) adds server-side encryption and CloudTrail audit logs
- Only the holder of the age private key (identity file) can decrypt

---

## Initial setup (first time)

### 1. Generate an age key pair

```bash
age-keygen -o ~/.config/homeops/identity.age
```

This writes both the private key and a comment line with the public key to `identity.age`.  
Extract the public key (recipient) for sharing or backup:

```bash
grep 'public key' ~/.config/homeops/identity.age
# age1... (copy this value)
```

Store the public key in `~/.config/homeops/recipient.txt`:

```bash
echo "age1<YOUR_PUBLIC_KEY>" > ~/.config/homeops/recipient.txt
```

> ⚠️ The private key file (`identity.age`) must never be committed or shared. Keep an encrypted offline backup.

### 2. Create the initial inventory

```bash
mkdir -p .inventory
touch .inventory/nodes.yaml
touch .inventory/repos.yaml
touch .inventory/services.yaml
touch .inventory/backups.yaml
```

Populate each file per its JSON schema:
- `nodes.yaml` → [`schemas/nodes.schema.json`](../schemas/nodes.schema.json)
- `repos.yaml` → [`schemas/repos.schema.json`](../schemas/repos.schema.json)

### 3. Pack and upload

```bash
export HOMEOPS_INVENTORY_URI=s3://<YOUR_BUCKET>/<YOUR_PATH>/homeops-inventory.tar.age
export HOMEOPS_AGE_RECIPIENT_FILE=~/.config/homeops/recipient.txt
./scripts/pack-inventory.sh
```

---

## Day-to-day workflow

### Fetch (decrypt) inventory

```bash
export HOMEOPS_INVENTORY_URI=s3://<YOUR_BUCKET>/<YOUR_PATH>/homeops-inventory.tar.age
./scripts/fetch-inventory.sh
```

### Edit inventory

Edit files in `.inventory/` directly. Validate with:

```bash
./scripts/healthcheck.sh
```

### Push updated inventory

```bash
./scripts/pack-inventory.sh
```

---

## Key rotation

If the age identity is compromised or you want to re-key:

1. Generate a new key pair:
   ```bash
   age-keygen -o ~/.config/homeops/identity-new.age
   ```
2. Fetch current inventory with the **old** key:
   ```bash
   HOMEOPS_AGE_KEY_FILE=~/.config/homeops/identity-old.age ./scripts/fetch-inventory.sh
   ```
3. Update `recipient.txt` with the new public key
4. Re-pack with the **new** recipient:
   ```bash
   HOMEOPS_AGE_RECIPIENT_FILE=~/.config/homeops/recipient-new.txt ./scripts/pack-inventory.sh
   ```
5. Securely shred the old identity file and revoke S3 access for old credentials

---

## S3 bucket policy recommendations

- Enable **S3 Versioning** so previous inventory bundles can be recovered
- Enable **S3 SSE-KMS** for server-side encryption with CloudTrail audit
- Restrict bucket access to a dedicated IAM user/role with least-privilege
- Enable **S3 Object Lock** (Compliance mode) for immutable backup retention

> Do not store the S3 bucket name, AWS account ID, or IAM credentials in this repository.

---

## Emergency recovery

If the age identity file is lost:

1. Check encrypted offline backups for the identity file
2. If unrecoverable, the encrypted bundle cannot be decrypted — rebuild inventory from scratch using monitoring data and node documentation
3. Create a new key pair and re-establish the inventory from observation of running systems
