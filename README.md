# homeops-control-plane

> **Public-safe** GitHub repo for HomeOps automation, runbooks, and schemas.  
> No real topology, IPs, hostnames, credentials, or service maps are stored here.

---

## Overview

This repository contains **generic** scripts, schemas, and runbooks for managing a home lab / home ops environment. All site-specific configuration (node names, LAN IPs, SSH usernames, WireGuard peers, S3 bucket names, Cloudflare tunnel IDs, service-to-host mappings, and credentials) lives **outside** this repo in an encrypted inventory bundle.

```
GitHub repo (public-safe)          Encrypted S3 bundle
─────────────────────────          ──────────────────────────────
scripts/                           homeops-inventory.tar.age
schemas/                             ├── nodes.yaml
runbooks/                            ├── repos.yaml
AGENTS.md                            ├── services.yaml
README.md                            └── backups.yaml
.gitignore
```

---

## Security model

| What                              | Where              |
|-----------------------------------|--------------------|
| Generic scripts & runbooks        | This GitHub repo   |
| JSON schemas for inventory files  | This GitHub repo   |
| Real node names, LAN IPs          | S3 (age-encrypted) |
| SSH usernames / keys              | S3 (age-encrypted) |
| WireGuard peer configs            | S3 (age-encrypted) |
| Cloudflare tunnel IDs             | S3 (age-encrypted) |
| S3 bucket names / paths           | Local env vars     |
| Service-to-host mappings          | S3 (age-encrypted) |
| Credentials / secrets             | Never committed    |

`.inventory/` is always gitignored and must **never** be committed.

---

## Quick start

### Prerequisites

- [age](https://github.com/FiloSottile/age) – client-side encryption/decryption
- [AWS CLI](https://aws.amazon.com/cli/) – S3 access
- bash ≥ 4, coreutils, jq (for healthcheck)

### Fetch inventory

```bash
export HOMEOPS_INVENTORY_URI=s3://example-placeholder/homeops-inventory.tar.age
export HOMEOPS_AGE_KEY_FILE=~/.config/homeops/identity.age  # optional; defaults to this path
./scripts/fetch-inventory.sh
```

After a successful run, `.inventory/` will contain:

```
.inventory/
  nodes.yaml
  repos.yaml
  services.yaml
  backups.yaml
```

### Pack (upload) inventory

```bash
export HOMEOPS_INVENTORY_URI=s3://example-placeholder/homeops-inventory.tar.age
export HOMEOPS_AGE_RECIPIENT_FILE=~/.config/homeops/recipient.txt  # age public key
./scripts/pack-inventory.sh
```

### Healthcheck

```bash
./scripts/healthcheck.sh
```

---

## Repository layout

```
.
├── AGENTS.md                         Agent / AI assistant instructions
├── README.md                         This file
├── .gitignore
├── schemas/
│   ├── nodes.schema.json             JSON Schema for nodes.yaml
│   └── repos.schema.json             JSON Schema for repos.yaml
├── scripts/
│   ├── fetch-inventory.sh            Download & decrypt inventory from S3
│   ├── pack-inventory.sh             Encrypt & upload inventory to S3
│   └── healthcheck.sh                Validate local inventory files
└── runbooks/
    ├── debian-workstation-conversion.md
    ├── secure-inventory.md
    ├── node-maintenance.md
    └── cold-storage-backup.md
```

---

## Runbooks

| Runbook | Purpose |
|---------|---------|
| [debian-workstation-conversion.md](runbooks/debian-workstation-conversion.md) | Windows → Debian workstation migration |
| [secure-inventory.md](runbooks/secure-inventory.md) | How to manage the encrypted inventory bundle |
| [node-maintenance.md](runbooks/node-maintenance.md) | mdadm RAID rebuild, OS updates, reboots |
| [cold-storage-backup.md](runbooks/cold-storage-backup.md) | Offline / cold-storage backup and restore |

---

## Contributing

All commits must pass `shellcheck` on shell scripts.  
Never commit real hostnames, IPs, credentials, or topology data.
