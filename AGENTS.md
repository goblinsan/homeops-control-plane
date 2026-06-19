# AGENTS.md — Instructions for AI Agents

This file provides authoritative guidance for any AI agent (Copilot, Claude, GPT, etc.) working in this repository.

---

## What this repo is

`homeops-control-plane` is a **public-safe** GitHub repository that contains:

- Generic shell scripts for fetching and packing an encrypted inventory
- JSON schemas that define the shape of inventory files
- Runbooks for home lab operations

It does **not** contain — and must **never** contain — any of the following:

| Forbidden content | Examples |
|-------------------|----------|
| LAN IP addresses | `192.168.x.x`, `10.x.x.x`, `172.16.x.x` |
| Hostnames or node names | `nas01`, `pi-hole`, `proxmox-1` |
| SSH usernames or key material | `user@host`, private keys |
| WireGuard peer configs | public keys, endpoints, allowed-IPs |
| Cloudflare tunnel IDs or tokens | UUIDs, `CF_TUNNEL_TOKEN` values |
| S3 bucket names or paths | real bucket names in code or comments |
| Service-to-host mappings | which service runs on which machine |
| Credentials or secrets | passwords, API tokens, environment files |

---

## Directory structure

```
.
├── AGENTS.md            ← you are here
├── README.md
├── .gitignore
├── schemas/             ← JSON Schema files (generic, no real data)
├── scripts/             ← Shell scripts (shellcheck-clean)
└── runbooks/            ← Markdown runbooks (no private details)
```

---

## Rules for agents

1. **Never commit real topology.** Use placeholders like `<NODE_NAME>`, `<LAN_IP>`, `<BUCKET_NAME>`.
2. **Never hard-code secrets.** Use environment variables; document them in README.md or the relevant runbook.
3. **Scripts must be shellcheck-friendly.** Run `shellcheck scripts/*.sh` before proposing a script change.
4. **No destructive disk commands without explicit user confirmation gates.** Any command that writes to a block device, formats a filesystem, or modifies a partition table must be behind a clear `read -p "Type YES to continue:"` guard with commentary explaining the risk.
5. **`.inventory/` is gitignored.** Do not treat `.inventory/` as source-of-truth for committed repository content, public-safe documentation, or example config. It may be used as source-of-truth for local runtime materialization, generated untracked `.env` files, and private deployment inputs, provided those derived artifacts are not committed back to any public-safe repository.
6. **Runbooks stay high-level.** Describe the process (e.g., "run mdadm --manage ... --add <device>") without referencing real device names or hostnames from the operator's environment.
7. **Schema files use placeholder values.** Examples in JSON schemas must use `"example.com"`, `"<node-name>"`, etc.
8. **Environment variables for configuration.** Any site-specific path, bucket, or URI must be sourced from an environment variable documented in the script header.

---

## Inventory workflow (for agent context)

The encrypted inventory is managed externally. The fetch flow is:

```
S3 (age-encrypted .tar.age)
        │
        ▼  scripts/fetch-inventory.sh
        │   1. aws s3 cp $HOMEOPS_INVENTORY_URI /tmp/homeops-inventory.tar.age
        │   2. age --decrypt ... → homeops-inventory.tar
        │   3. tar xf → .inventory/{nodes,repos,services,backups}.yaml
        ▼
.inventory/   (gitignored, local only)
```

The pack flow is the reverse:

```
.inventory/   (local edits)
        │
        ▼  scripts/pack-inventory.sh
        │   1. tar cf homeops-inventory.tar .inventory/
        │   2. age --encrypt ... → homeops-inventory.tar.age
        │   3. aws s3 cp homeops-inventory.tar.age $HOMEOPS_INVENTORY_URI
        ▼
S3 (updated bundle)
```

---

## Private inventory read order

If `.inventory/` is present locally, agents should orient themselves in this order before planning environment changes:

1. `.inventory/current-system-overview.md`
2. `.inventory/current-system-overview.yaml`
3. `.inventory/nodes.yaml`
4. `.inventory/services.yaml`
5. `.inventory/repos.yaml`
6. `.inventory/backups.yaml`
7. `.inventory/agent-handoff.local.md`

Important:

- Treat `.inventory/current-system-overview.{md,yaml}` as the canonical short-form view of the current environment.
- Treat `.inventory/agent-handoff.local.md` as supporting history, recent changes, and detailed notes, not as the first document to anchor on.
- Do not infer that the environment is greenfield just because a plan document proposes new architecture.
- Do not assume a single deployment model across the system; confirm whether a service is a managed app, a remote workload, or an internal stateful Compose service.
- If the short-form overview conflicts with older session-log notes, prefer the overview unless the user says otherwise or you verify a more recent change.

---

## Validation

Before proposing a PR:

- `shellcheck scripts/*.sh` — must pass with no errors or warnings
- `jq . schemas/*.json` — must be valid JSON
- Confirm `.inventory/` is not tracked: `git ls-files .inventory/` must return nothing
