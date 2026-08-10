# Autonomous Workforce Phase 5: Local-Only Pilot

Executes the plan's smallest credible slice
(`docs/autonomous-workforce/plan-v2.md`, Phase 5): one human-authored task,
one repository, the local backend, ending in a Forgejo PR and a review-ready
task — with no manual coding intervention, no premium provider, and no
escalation.

Public-safe: real hostnames, usernames, and tokens stay in the private
inventory and secret tooling.

## Stage 0 — Rehearsal (already automated)

`task-flow-conductor` ships the full pilot as an offline rehearsal:

```bash
npm run pilot:e2e
```

It boots a real project-dashboard on ephemeral PGlite, seeds a real git
origin, runs the real dispatcher/runner/worktree/trusted-git stack with a
deterministic fake model and an in-process fake Forgejo, and checks 17 exit
criteria including: PR created from the attempt branch, `main` untouched,
task derived review-ready, worktrees cleaned, and crash recovery (PR
created, conductor dies, lease expires, sweep recovers attempt and task).
Run it after any conductor change to the execution path. It requires a
built `project-dashboard` sibling checkout (`npm run build` there).

## Prerequisites for the live pilot

- [ ] Phase 2 runbook completed for the pilot repository
      (`runbooks/autonomous-workforce-phase2-enforcement.md`): branch
      protection verified, bot collaborator at `write`, scoped token stored,
      deploy hooks audited or absent.
- [ ] `feature/attempt-runner-3a` reviewed and merged in
      `task-flow-conductor`; project-dashboard main already carries the
      Phase 1 schema.
- [ ] A dedicated non-privileged execution user on the conductor host with
      its own checkout root (`EXECUTION_CHECKOUT_ROOT`) — the pilot runs the
      production-shaped isolation model, not a shortcut.
- [ ] Pilot repository chosen: an AssetForge repo or a scratch repo,
      Forgejo-canonical, with a real validation command.

## Stage 1 — Register the pilot in project-dashboard

Keep everything else non-autonomous; enable exactly one project and one
repository.

1. Ensure the pilot project row has `automation_enabled = true` and
   `max_concurrent_tasks = 1`. All other projects keep the default `false`.
2. Ensure the repository row has `scm_provider = 'forgejo'`,
   `canonical_remote` set to the Forgejo clone URL, `bot_credential_ref`
   pointing at the scoped token, and — last — `write_enabled = true`,
   `pr_enabled = true`.
3. Author one small, well-scoped task (single-file change with clear
   acceptance criteria) with `selected_repository_id` set to the pilot
   repository and status `open`.

## Stage 2 — Conductor environment

In the conductor's `.env` (never committed):

```text
EXECUTION_DISPATCH_ENABLED=1
EXECUTION_PROJECT_IDS=<pilot project id>
EXECUTION_MAX_CONCURRENT=1
EXECUTION_CHECKOUT_ROOT=<execution user's checkout root>
EXECUTION_LOCAL_MODEL=<local model id>
EXECUTION_VALIDATION_COMMANDS=<repo validation command(s), comma-separated>
FORGEJO_BASE_URL=<forge base url>
FORGEJO_API_TOKEN=<read-only token for protection verification>
FORGEJO_BOT_USERNAME=conductor-bot
FORGEJO_BOT_TOKEN=<scoped bot token for the pilot repo>
```

Start the conductor service. `GET /execution/status` shows the dispatcher
state; `POST /execution/pause` is the runtime kill switch.

## Stage 3 — Observe the run

Success path, all visible in the dashboard:

1. attempt row created (`claimed` → `running`) with the persisted policy
   snapshot and selection reason
2. branch `conductor/task-N-attempt-1` appears on the Forgejo repo
3. validation recorded as `passed`; secret scan silent
4. PR exists targeting the default branch; attempt `succeeded` with PR
   metadata
5. task status `in_review`; `GET /portfolio?state=awaiting_review` lists it
6. worktree directory removed

Exit criteria beyond the happy path:

- [ ] kill the conductor mid-attempt (`kill -9`), restart it, and confirm
      the startup sweep reconciles: attempt recovered as `succeeded` if the
      PR survived, otherwise `failed` with the task back to `open`
- [ ] confirm the bot cannot push `main` and cannot merge the PR (attempt
      both in the Forgejo UI as the bot if desired — both must be refused)
- [ ] human reviews and merges the PR in Forgejo; task is marked `done` by
      the human

## Failure handling

- Attempt `blocked` + `policy_blocked`: the protection verification failed —
  re-run the Phase 2 `--verify` script and fix the repo configuration.
- Attempt `failed` + `validation_failed` / `patch_apply_failed`: normal
  local-model failure; the task reopens for one retry, then blocks
  `human_required` per `EXECUTION_MAX_ATTEMPTS_PER_TASK`.
- Repeated failures pause the repository via the breaker;
  `GET /execution/status` shows open breakers.
- Anything surprising: `POST /execution/pause`, investigate, resume.

## After the pilot

Record the outcome (attempt ids, durations, failure categories) in the
dashboard notes. Only then consider widening: a second task, then a second
repository, then `EXECUTION_MAX_CONCURRENT=2`. Phase 6 (Claude backend,
escalation, premium budget caps) starts only after the local pipeline is
boring.

## Phase 6 — Enabling premium escalation (after the local pipeline is boring)

The Claude backend ships default-off. It drives the Claude Code CLI
headlessly in the isolated worktree (file tools only, no Bash, no git, no
SCM credentials in its environment) and records cost/token actuals per
attempt. To enable, add to the conductor `.env` and restart:

```text
EXECUTION_PREMIUM_ENABLED=1
EXECUTION_PREMIUM_DAILY_USD=10
EXECUTION_CLAUDE_MAX_COST_USD=3
EXECUTION_CLAUDE_MODEL=claude-opus-5
```

The conductor host must have the `claude` CLI installed and authenticated.
Behavior once enabled:

- tasks with `execution_complexity: "high"` route directly to Claude
- local failures with an escalation-eligible category (validation_failed,
  capability_gap, context_too_large, patch_apply_failed, model_timeout)
  escalate to one Claude child attempt (`parent_attempt_id` links them;
  raise with EXECUTION_PREMIUM_MAX_ATTEMPTS)
- the daily USD cap halts all premium dispatch when spent (local
  continues); per-attempt cost breaches record `budget_exhausted`
- `GET /execution/status` shows the premium ledger alongside the breakers

First premium pilot: author one task the 14B has already failed (task 153
on pilot-sandbox is the natural candidate — reopen it) and watch the
escalation chain land a PR.
