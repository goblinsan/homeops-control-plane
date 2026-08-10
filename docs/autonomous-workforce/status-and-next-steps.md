# Autonomous Workforce — Status and Next Steps

Status date: 2026-08-10, rev 2. Companion to `plan-v2.md` (the approved
architecture baseline). Reviewed and **approved (N1–N4) with sequencing
changes**, all incorporated below: per-repository validation promoted to a
rollout prerequisite, a node crash/recovery acceptance criterion, a
stronger definition of the AssetForge stage, human review-outcome capture
added as N3.4, and the project objective reframed from building the
workforce to using it. Public-safe: no hostnames, credentials, or private
topology.

---

## Where things stand

**Every phase of the MVP plan is implemented and both pilots have run
successfully.**

| Phase | Status | Evidence |
| --- | --- | --- |
| 1 — Schema & persistence | Merged, deployed | project-dashboard schema 2.6.0: attempts, repository leases, claims API, `GET /portfolio` |
| 2 — Enforcement setup | Tooling shipped; provisioned on the pilot repo | Branch protection verified on `pilot-sandbox`; bot push-to-main and PR-merge refused empirically |
| 3A/B/C — Runner, local backend, Forgejo adapter | Merged | `src/execution/` in task-flow-conductor; 100+ execution tests |
| 4 — Dispatch, policy, breakers, recovery | Merged | Claim loop, kill switch, per-repo + global breakers, crash-recovery sweep |
| 5 — Local-only pilot | **Executed live** | Task 152 → PR #1 by the local 14B, merged by human |
| 6 — Claude backend, budgets, escalation | Merged | Task 153 → PR #2 by claude-opus-5 after 4 local failures; $0.13, validation passed, merged by human |

The invariants held throughout: no push to `main`, no autonomous merge, no
secret in a commit, every attempt cost- and token-metered, human merge as
the only path to deployment.

**The phased pilot approach paid for itself.** Eight real defects were
found by running the system rather than reviewing it, including: the local
backend prompting without file contents; heartbeat cadence outliving short
leases; task-status settling missing entirely (review-ready could never
derive); zero-work CLI errors burning attempts; and premium budgets being
consumed by attempts where the provider never ran. All fixed with tests.

## Current deployment state (and its known shortcuts)

- **project-dashboard**: deployed normally, carries all portfolio state.
- **task-flow-conductor**: running on the operator's Mac, dispatch
  **paused**. This is a pilot shortcut, not the target: no dedicated
  execution user, subscription OAuth for the Claude CLI, and the operator's
  provisioning token doing double duty as the protection-verification
  token.
- **Pilot residue to clean up**: `EXECUTION_MAX_ATTEMPTS_PER_TASK=8` (a
  pilot-only widening; default is 2), premium flag enabled in the Mac
  `.env`, two tokens due for rotation (the provisioning token, and the bot
  token that was once echoed to a terminal), and the `pilot-sandbox` repo
  itself.
- **Known in-memory state**: circuit breakers and the premium ledger reset
  on conductor restart. Acceptable at concurrency 1; revisit before
  multi-stream rollout.
- **Validation commands** come from conductor env, not from workflow
  profiles — a deliberate Phase 4 simplification.

---

## Proposed next steps

Ordered; each numbered item is independently acceptable or rejectable.

### N1 — Post-pilot hygiene (small, do first)

1. Rotate the bot token and replace the provisioning token with a
   dedicated read-scoped token for `FORGEJO_API_TOKEN`, per the rotation
   runbook.
2. Revert `EXECUTION_MAX_ATTEMPTS_PER_TASK` to default; decide the
   standing premium posture on the Mac (recommend: leave
   `EXECUTION_PREMIUM_ENABLED=1` but keep dispatch paused).
3. Keep `pilot-sandbox` as the permanent smoke-test repo (recommended)
   or archive it.

### N2 — Move the conductor to a node (the real productionization step)

The conductor is a normal deployable service; this is packaging, not new
architecture:

1. Pick the host node; create the dedicated non-privileged execution user
   with its own checkout root (the isolation model the runbook already
   specifies).
2. Deploy via the existing homeops deploy flow; `.env` assembled from
   secret tooling: bot token, scoped read token, dashboard URL, and an
   **Anthropic API key** (not subscription OAuth) so premium runs are
   independently billed, metered, and revocable.
3. Node acceptance criteria, in order — the Mac conductor is not retired
   until all pass on the node:

   ```text
   deploy → npm run pilot:e2e → live pilot-sandbox smoke task
   → kill conductor during a controlled attempt → lease expires
   → restart → verify reconciliation, no duplicate side effects
   → retire Mac conductor
   ```

### N3 — Close the deliberate simplifications

**N3.1 — Per-repository validation (rollout prerequisite).** Wire
validation commands from the repository/workflow-profile record instead of
conductor env. Environment-level validation is acceptable for exactly one
repository; this must land between node productionization and enabling
AssetForge:

```text
node productionized → repo/workflow validation wired → AssetForge enabled
```

**N3.2 — Attempt artifacts (non-blocking).** Publish backend selection,
validation output, and the premium summary as dashboard artifacts via
`artifacts.attempt_id` (the column exists; nothing writes it yet). Improves
auditability; does not gate rollout.

**N3.3 — Dashboard affordances (non-blocking).** Mark-done action and a
portfolio UI surface — usability, not safety.

**N3.4 — Human review-outcome capture (new, from review).** Machine
telemetry misses the most important quality signal: what happened in human
review. Add a lightweight per-PR outcome recorded on the succeeding
attempt — `accepted_as_is` | `accepted_with_minor_edits` |
`accepted_with_major_edits` | `rejected`, plus an optional short reason.
Future local/Claude/Codex comparisons must weigh review burden alongside
validation success and provider cost: a free local change requiring a major
rewrite is economically worse than a $0.13 premium change accepted as-is.
Keep it simple; no scoring system yet.

### N4 — Widen the rollout (plan Phase 7, strengthened per review)

The question changes from "can the system create a PR?" to **"does the
system create useful project progress while the operator is doing
something else?"** One repository at a time, each gated on the Phase 2
enforcement runbook:

1. **AssetForge gets real work, not another smoke test**: 3–5 deliberately
   selected tasks at concurrency 1 — independently scoped, useful,
   low-risk, objectively testable where practical. Evaluate the batch on:
   local success rate, failure categories, escalation rate, Claude success
   after escalation, time-to-review-ready, validation success, premium
   cost, human review effort (N3.4), and actual usefulness.
2. Then HomeOps/factory with several useful tasks, still at concurrency 1.
3. Concurrency rises only on evidence: **two different repositories**
   showing predictable behavior — not merely several AssetForge
   successes — and breaker state persisted/rebuilt across restarts first.

```text
AssetForge: 3–5 useful tasks → HomeOps: useful tasks
→ persist/rebuild breaker state → concurrency 2
→ Arremate → consider concurrency 3 from evidence
```

### N5 — Post-MVP tracks (explicitly deferred, in recommended order)

1. **Container-per-attempt** with an egress allowlist — the isolation end
   state; becomes more valuable as more repos are enabled.
2. **Codex backend** — only once there's benchmark evidence to route
   between premium providers; the `ExecutionBackend` slot is ready.
3. **agent-service integration** — revisit whether it should own local
   model routing; nothing currently duplicated enough to force it.
4. **Autonomous task generation** — remains out of scope pending its own
   review brief with its own invariants, as plan-v2 requires.

---

## Decisions (all accepted in review)

| # | Decision | Resolution |
| --- | --- | --- |
| D1 | Standing premium posture until node deploy | **Accepted** — enabled, dispatch paused |
| D2 | `pilot-sandbox` fate | **Accepted** — permanent smoke-test infrastructure (conductor upgrades, model changes, credential rotation, recovery tests) |
| D3 | Node + deploy mechanism | **Accepted** — existing HomeOps deployment model |
| D4 | Premium auth on the node | **Accepted** — dedicated Anthropic API key (independently revocable, measurable, budgetable) |
| D5 | Budget values | **Accepted** — $10/day, $3/attempt; configuration-driven, tuned from evidence |
| D6 | First real stream | **Accepted** — AssetForge |

## Objective going forward

The MVP objective — build the autonomous workforce — is achieved. The next
phase optimizes for **using** it:

> Keep multiple side-work streams making measurable, useful progress
> without requiring the operator to personally perform their
> implementation work.

Judge the system by useful PRs produced, human review effort, milestones
advanced, execution reliability, time-to-review-ready, and premium cost
per accepted change. The next milestone: **several useful AssetForge
changes appear as validated PRs while the operator spends no time
implementing them.**

## Approved immediate sequence

```text
N1: hygiene + credential rotation
→ N2: production node deployment
→ pilot:e2e + live smoke + crash/recovery smoke on the node
→ N3.1: per-repository/workflow validation
→ AssetForge: 3–5 real tasks, concurrency 1
   (in parallel: N3.4 review-outcome capture, N3.2 artifacts, N3.3 UI)
→ HomeOps: real tasks
→ persist/rebuild breaker state → concurrency 2 → Arremate
```

No additional architecture work is required before these steps.
