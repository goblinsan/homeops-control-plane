# Autonomous Workforce — Status and Next Steps

Status date: 2026-08-10. Companion to `plan-v2.md` (the approved
architecture baseline). Public-safe: no hostnames, credentials, or private
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
3. First action after deploy: run `npm run pilot:e2e` on the node, then
   one live smoke task through `pilot-sandbox`.
4. Retire the Mac conductor.

### N3 — Close the deliberate simplifications

1. Wire validation commands from the repository/workflow-profile record
   instead of conductor env (per-repo validation is required the moment a
   second repository is enabled).
2. Publish attempt artifacts: backend selection, validation output, and
   the premium summary as dashboard artifacts linked via
   `artifacts.attempt_id` (the column exists; nothing writes it yet).
3. Small dashboard affordances: a mark-done action and surfacing
   `GET /portfolio` in the UI, so task lifecycle doesn't require curl.

### N4 — Widen the rollout (plan Phase 7, unchanged)

One repository at a time, each gated on the Phase 2 enforcement runbook:

1. Register the AssetForge stream first (the plan's original pilot
   domain); enforce, enable, run a handful of real tasks at concurrency 1.
2. Then HomeOps/factory and Arremate/revenue streams.
3. Raise `EXECUTION_MAX_CONCURRENT` to 2–3 only after per-repo behavior is
   boring, and persist/rebuild breaker state across restarts before doing
   so.

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

## Decisions requested

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | Standing premium posture until node deploy | Enabled, dispatch paused |
| D2 | `pilot-sandbox` fate | Keep as permanent smoke-test target |
| D3 | Node + deploy mechanism for the conductor | Operator's call (existing deploy flow) |
| D4 | Premium auth on the node | Dedicated Anthropic API key |
| D5 | Budget values for real streams | Keep $10/day, $3/attempt until data says otherwise |
| D6 | First real stream | AssetForge |

Accepting N1–N4 with the D-column recommendations takes the system from
"proven pilot" to "production portfolio execution" with no new
architecture — everything above is packaging, hygiene, and the rollout the
plan already prescribes.
