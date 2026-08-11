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

### Bootstrap a first inventory locally

```bash
./scripts/init-inventory.sh
```

This creates placeholder-only local files in `.inventory/`:

```text
.inventory/
  nodes.yaml
  repos.yaml
  services.yaml
  backups.yaml
```

Replace the placeholder values with your real topology locally, then run `./scripts/pack-inventory.sh` to encrypt and upload the bundle.

The repo inventory is intended to capture not just clone URLs, but also:

- which node or nodes a repo deploys to
- which services it owns
- whether pushes auto-deploy
- which runner or workflow performs the deploy
- where the repo is checked out locally for maintenance

### Healthcheck

```bash
./scripts/healthcheck.sh
```

### SSH aliases

Render local SSH and HTTP-friendly host aliases from `.inventory/nodes.yaml`:

```bash
./scripts/render-ssh-config.sh --install-local
./scripts/render-hosts.sh --install-local
```

The generated OpenSSH config is written to `.inventory/ssh_config` and included
from `~/.ssh/config`. The generated hosts snippet is written to `.inventory/hosts`
and installed into `/etc/hosts` between managed markers. Real node names, LAN IPs,
usernames, and ports remain in the private inventory output and are not committed
to this repo.

---

## Repository layout

```
.
├── AGENTS.md                         Agent / AI assistant instructions
├── README.md                         This file
├── .gitignore
├── schemas/
│   ├── backups.schema.json           JSON Schema for backups.yaml
│   ├── nodes.schema.json             JSON Schema for nodes.yaml
│   ├── repos.schema.json             JSON Schema for repos.yaml
│   └── services.schema.json          JSON Schema for services.yaml
├── scripts/
│   ├── fetch-inventory.sh            Download & decrypt inventory from S3
│   ├── create-forgejo-repo.sh        Create a Forgejo/Gitea repo via API
│   ├── init-inventory.sh             Create local placeholder inventory files
│   ├── render-hosts.sh               Render local hosts aliases from inventory
│   ├── render-ssh-config.sh          Render local OpenSSH aliases from inventory
│   ├── pack-inventory.sh             Encrypt & upload inventory to S3
│   ├── healthcheck.sh                Validate local inventory files
│   └── rotate-postgres-app-credential.sh
│                                      Rotate a Postgres app role + remote DATABASE_URL safely
└── runbooks/
    ├── observability-alerting-foundation.md
    ├── debian-workstation-conversion.md
    ├── secure-inventory.md
    ├── node-maintenance.md
    ├── secret-rotation.md
    └── cold-storage-backup.md
```

---

## Runbooks

| Runbook | Purpose |
|---------|---------|
| [debian-workstation-conversion.md](runbooks/debian-workstation-conversion.md) | Windows → Debian workstation migration |
| [secure-inventory.md](runbooks/secure-inventory.md) | How to manage the encrypted inventory bundle |
| [node-maintenance.md](runbooks/node-maintenance.md) | mdadm RAID rebuild, OS updates, reboots |
| [observability-alerting-foundation.md](runbooks/observability-alerting-foundation.md) | Monitoring, alerting, mobile integration, and service onboarding contract |
| [secret-rotation.md](runbooks/secret-rotation.md) | Safe secret rotation patterns without printing values |
| [cold-storage-backup.md](runbooks/cold-storage-backup.md) | Offline / cold-storage backup and restore |

---

## First-time S3 setup

The bucket and object path are intentionally not stored in git. Configure them through local environment variables only.

Suggested bucket controls:

- Enable bucket versioning.
- Enable SSE-KMS on the bucket or at least on the inventory object prefix.
- Use a dedicated IAM principal with only `s3:GetObject`, `s3:PutObject`, and, if needed, `s3:ListBucket` for the relevant prefix.
- Keep the bundle path stable, for example `s3://<bucket>/<prefix>/homeops-inventory.tar.age`.

Suggested bootstrap order:

1. Generate an age key pair and save the recipient to `~/.config/homeops/recipient.txt`.
2. Create the S3 bucket and choose the inventory object path.
3. Export `HOMEOPS_INVENTORY_URI` locally in your shell profile or a non-committed env file.
4. Run `./scripts/init-inventory.sh`, replace placeholders with real inventory data, and validate with `./scripts/healthcheck.sh`.
5. Run `./scripts/pack-inventory.sh` to create and upload the first encrypted bundle.

---

## Contributing

All commits must pass `shellcheck` on shell scripts.  
Never commit real hostnames, IPs, credentials, or topology data.
