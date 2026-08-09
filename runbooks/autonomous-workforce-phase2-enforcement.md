# Autonomous Workforce Phase 2: Enforcement Setup

Implements the "Enforcement Model" of
`docs/autonomous-workforce/plan-v2.md`. After this runbook, "never push
main" and "never merge" are properties of Forgejo configuration and
credential scope — true even if every line of conductor code is wrong. No
autonomous SCM write may happen before this runbook has been completed for
the target repository.

This document is public-safe: real hostnames, usernames, and tokens stay in
the private inventory and secret tooling.

## Scope

Run this once per candidate pilot repository. Initial candidates:

| Repository | Deploy automation on main? | Hook audit required |
| --- | --- | --- |
| the AssetForge pilot repo (or a scratch repo) | no | no |
| `project-dashboard` | yes (post-receive) | yes |

Repositories without deploy automation still get branch protection and a
scoped bot identity; the hook audit step is a no-op for them.

## Prerequisites

- Admin token for the Forgejo instance in `FORGEJO_TOKEN`, instance URL in
  `FORGEJO_BASE_URL` (same convention as `scripts/create-forgejo-repo.sh`).
- `curl` and `jq`.
- The repository is Forgejo-canonical. Dual-remote repositories where GitHub
  is canonical are ineligible for enforcement setup — migrate first.

## Step 1 — Create the bot identity (once, operator-only)

Create a dedicated bot user (suggested name: `conductor-bot`) in the Forgejo
admin UI. Rules:

- no admin flag, no org ownership, not a member of any team with elevated
  repo permissions
- no SSH keys beyond what the conductor host needs
- one bot identity is acceptable for the pilot; per-repo tokens (Step 4)
  provide the per-repo scoping

## Step 2 — Branch protection + collaborator wiring (per repo)

```bash
./scripts/forgejo-branch-protection.sh \
  --owner <owner> --repo <repo> --branch main \
  --allow-user <your-operator-username> \
  --bot conductor-bot \
  --apply
```

This is idempotent. It creates or updates a protection rule on `main` that:

- restricts direct pushes to the `--allow-user` list (your existing
  push-to-main deploy flow keeps working; the bot cannot push main)
- restricts merges to the same list (the bot cannot merge its own PRs)
- adds the bot as a plain `write` collaborator (branch pushes and PR
  creation only)

Verify (also the check the conductor will run before its first write in
Phase 3A):

```bash
./scripts/forgejo-branch-protection.sh \
  --owner <owner> --repo <repo> --branch main \
  --bot conductor-bot \
  --verify
```

## Step 3 — Deploy-hook audit (per repo with deploy automation)

```bash
./scripts/audit-forgejo-deploy-hooks.sh --owner <owner> --repo <repo>
```

The script prints every active server-side git hook and push webhook with a
heuristic verdict. **The heuristic is advisory — the audit is complete only
when a human has read the printed hook content** and confirmed non-main refs
are ignored. A hook that deploys on any ref must be fixed before the
repository may be write-enabled; a bot branch push must never deploy.

Record the audit date and outcome in the private inventory alongside the
repository entry.

## Step 4 — Scoped bot token (per repo, operator-only)

Logged in **as the bot user**, create a scoped access token
(user settings → applications):

- token name: `conductor-<repo>` (one token per repository)
- scopes: `write:repository`, `read:user` — nothing else; never
  `write:admin`, never org scopes

Store the token in the secret tooling under a reference name (suggested:
`forgejo/conductor-bot/<repo>`), then follow `runbooks/secret-rotation.md`
conventions for rotation. Tokens are handled only by the operator and the
trusted AttemptRunner SCM helper — never by the coding backend, never in a
worktree, never in chat or committed content.

## Step 5 — Register the credential reference in project-dashboard

Wire the *reference* (not the token) and the SCM policy metadata onto the
repository row. `write_enabled` stays `false` — it flips only at pilot time
(Phase 5):

```bash
curl -sS -X PATCH "$DASHBOARD_URL/projects/<projectId>/repositories/<repoId>" \
  -H 'Content-Type: application/json' \
  --data '{
    "scm_provider": "forgejo",
    "canonical_remote": "<forgejo clone url>",
    "bot_credential_ref": "forgejo/conductor-bot/<repo>",
    "auto_deploy_on_main": <true|false as audited>
  }'
```

## Step 6 — Completion checklist (per repo)

- [ ] protection rule on `main`: bot excluded from push and merge
      allowlists (`--verify` exits 0)
- [ ] bot collaborator permission is exactly `write`
- [ ] deploy hooks audited by a human, or repository has no deploy
      automation
- [ ] scoped token exists, stored in secret tooling; `bot_credential_ref`
      set on the repository row
- [ ] `write_enabled` is still `false`

When every box is checked for a repository, it is a valid Phase 5 pilot
target. The remaining Phase 2 item — the conductor refusing to dispatch when
`--verify` fails — lands with the conductor work in Phase 3A.
