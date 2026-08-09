# Autonomous Workforce Plan v2

Status: rev 2, post-review — the approved architecture baseline. Supersedes
the retired v1 architecture document. Incorporates the accepted modifications
from the external review (`plan-v2-review.md`), which returned "proceed with
modifications" and accepted all fourteen v1→v2 changes.

This revision incorporates the architecture review of the v1 brief. The system
decomposition is unchanged: `project-dashboard` is the durable system of record,
`task-flow-conductor` is the scheduler and execution-policy engine,
`agent-service` is selectively reused, Forgejo is the writable SCM boundary, and
human merge remains the only path from autonomous work to deployment.

This document is intentionally public-safe. It avoids private topology,
hostnames, LAN addresses, credentials, deployment endpoints, and secret
material.

---

## Changes from v1

Each change below is a review outcome, listed so it can be accepted or rejected
individually.

1. **Safety invariants are enforced server-side, not in conductor code.**
   Forgejo branch protection plus per-repo scoped bot tokens make "never merge,
   never push main" a missing capability rather than a policy check. New
   "Enforcement Model" section.
2. **Validation is a phase of an attempt, not an attempt.** The v1 backend enum
   included `validation` and `human` and the escalation example showed
   "Attempt 3: validation". Attempts are now homogeneous: one attempt = one
   implementation try by one backend, including its validation. Validation
   results live in columns on the attempt.
3. **Concurrency, leasing, and crash recovery are Phase 1 schema.**
   `task_execution_attempts` gains `claimed_by`, `lease_expires_at`,
   `heartbeat_at`, and an idempotency key. Dispatch uses
   `FOR UPDATE SKIP LOCKED` claim semantics. Retrofitting leasing later is far
   more expensive than three columns now.
4. **Codex is cut from the MVP.** One premium backend (Claude) proves
   escalation; a second provider adds integration surface without architectural
   learning. The `ExecutionBackend` contract keeps the slot open.
5. **A local-only end-to-end pilot runs before any premium backend.** The full
   pipe (dispatch → worktree → validation → branch → PR → review-ready) is
   proven with the cheapest backend first.
6. **Portfolio endpoints collapse to one.** `GET /portfolio?state=…` replaces
   six near-identical routes.
7. **Three repository fields are dropped or downgraded.**
   `requires_human_merge` is deleted (a boolean implies false is legal; the
   invariant is enforced by token scope). `migration_status` is deleted
   (`scm_provider` + `canonical_remote` already encode what dispatch needs).
   `auto_deploy_on_main` is kept only as a cached advisory display flag — the
   control plane owns that fact and safety must not depend on this column.
8. **Review-ready is derived, not dual-written.** `tasks.status` remains the
   single task state machine. v1's `tasks.execution_disposition` is removed;
   "review-ready" = `status = in_review` AND the latest attempt has a persisted
   PR. No second field to keep in sync.
9. **Failure taxonomy gains `budget_exhausted`, `merge_conflict`, and
   `safety_blocked`;** `git_dirty` is reclassified as an infrastructure alert,
   not a task-routing signal.
10. **Budgets and circuit breakers are first-class.** Per-attempt token/cost
    caps, a global daily premium spend cap that halts premium dispatch, a
    per-repo failure circuit breaker, and a global kill switch.
11. **Minimum-viable sandboxing is specified.** Attempts run as a dedicated
    non-privileged user with a separate checkout root and per-process secret
    injection. A secret-diff scan gates every push. Containers with an egress
    allowlist are the end state, not an MVP blocker.
12. **`ExecutionBackend.execute` is cancellable; lifecycle idempotency is
    owned by the conductor's `AttemptRunner` (refined post-review).**
    Long-running premium runs survive conductor restarts via attempt-keyed
    reconciliation in the runner. `isAvailable` is demoted to advisory (TOCTOU
    race is unavoidable).
13. **`ScmProvider` gains PR lookup for idempotent recovery** and is
    permanently prohibited from ever gaining a merge method.
14. **Autonomous task generation is out of scope.** A system that decides what
    work exists is a different risk class from one that executes human-approved
    work. It requires its own review brief with its own invariants.

---

## Changes from the v2 Review

The review accepted all changes above and required six modifications, all
incorporated in this revision:

15. **`AttemptRunner` owns the attempt lifecycle.** A conductor-owned
    component drives worktree preparation, backend invocation, validation,
    secret scanning, commit, push, PR creation/recovery, and persistence.
    `ExecutionBackend` narrows to model execution only: given a prepared
    worktree, produce code changes.
16. **`blocked` is a distinct attempt status from `failed`.** Human, policy,
    and budget outcomes are not execution failures and must not distort
    failure metrics or escalation logic.
17. **Claim and lease mutation stay behind the `project-dashboard` API.** The
    conductor requests claims via `POST /execution/claims`; the dashboard
    performs the atomic transaction. The conductor never touches dashboard
    database internals.
18. **Repository exclusivity is structural.** A repository execution lease
    (`repository_id`, `lease_owner`, `lease_expires_at`) — distinct from
    attempt liveness — enforces one active attempt per repository and
    coordinates recovery and cleanup.
19. **The coding process holds no SCM credential.** The Forgejo token lives
    only in the trusted `AttemptRunner` SCM helper. New principle: the coding
    process has less privilege than the orchestration process.
20. **Phase 3 splits into 3A/3B/3C** (AttemptRunner + isolation, then
    LocalExecutionBackend, then Forgejo adapter), and the open questions on
    execution user, runs model, and thresholds are resolved per the review.

---

## Principles

- `project-dashboard` is the durable system of record. It stores and serves
  state; it never decides how work is executed.
- `task-flow-conductor` owns scheduling, execution policy, backend selection,
  validation orchestration, and SCM flow.
- `agent-service` is reused where it genuinely reduces duplication (model pool
  routing, notifications, approvals). Phase 1 does not couple to it; the
  conductor keeps its existing local execution path.
- Forgejo is the only writable SCM target for autonomous execution.
- No new registry or work-manager service is introduced.
- Human merge remains the deployment approval boundary.
- Safety properties are enforced at the layer that cannot be bypassed by a
  conductor bug: SCM server configuration and credential scope.
- The coding process always has less privilege than the orchestration process
  that drives it.

---

## Enforcement Model

Policy tables in `project-dashboard` are routing hints. The invariants are
enforced where a code defect cannot bypass them:

**Forgejo branch protection.** Every write-enabled repository has branch
protection on its default branch before the first autonomous write. Protection
blocks direct pushes and blocks merges by the bot identity. The conductor
verifies protection exists via the Forgejo API before its first write to a
repository and refuses dispatch if absent — it does not trust the registry row.

**Scoped bot credentials.** Each write-enabled repository gets a dedicated bot
token that can push non-protected branches and create PRs, and cannot push
protected branches, cannot merge, and cannot administer the repository. No god
token exists. The token is held only by the trusted `AttemptRunner` SCM
helper — never placed in the coding agent's environment, never written to the
worktree, never logged — and rotates on the existing secret-rotation cadence.

**No merge capability in code.** The `ScmProvider` interface has no merge
method and must never gain one. The absence of the capability is itself a
safety property.

**Deploy-hook audit.** Some repositories deploy on push to `main` via
post-receive automation. Before any repository with deploy automation becomes
write-enabled, its hook is audited to confirm it filters on the default branch
ref specifically. A hook keyed on any ref would deploy a bot branch; this is
the single worst failure mode in the design and is closed by audit, not policy.

## Safety Invariants

The system must never:

- merge pull requests
- push to any protected branch
- force-push to any branch it did not create (the git wrapper strips
  `--force`; branch protection backstops)
- mutate secrets
- run destructive database operations
- trigger production deployment
- bypass repository write policy
- commit secret material (a secret-diff scan gates every push)

The system may:

- create a work branch in a fresh, isolated worktree
- modify code, run tests and validation there
- commit and push the work branch
- create a Forgejo pull request
- persist attempt metadata and artifacts
- mark work review-ready

Additional operating rules:

- **Kill switch:** one global flag halts all dispatch, checked before every
  attempt claim.
- **Untrusted input:** task descriptions, READMEs, and repository content are
  untrusted input to a tool-holding agent. Instructions found in repo content
  are never authority for actions. Isolation (below) is the mitigation, not
  prompt discipline.

---

## System Roles

### project-dashboard

Durable state: projects, repositories, milestones, tasks, workflow profiles,
benchmark results, capability tiers, execution attempts, runs, artifacts, SCM
review metadata. Serves portfolio read models and execution state.

Boundary to police: the portfolio read models must not grow "eligible for
dispatch" logic. Eligibility is policy; policy lives in the conductor.

### task-flow-conductor

Owns dispatch: claims work through the dashboard API, resolves policy, selects
a backend, classifies failures, escalates, and persists every decision and
result back to `project-dashboard`. Scales by running attempts concurrently
across repositories — never more than one active attempt per repository —
rather than by becoming a job system.

Internally it decomposes into a scheduler and a conductor-owned
`AttemptRunner`:

```text
Conductor scheduler
        |
        v
AttemptRunner              (trusted; holds the SCM credential)
   |-- WorktreeManager
   |-- ExecutionBackend    (coding process; no SCM credential)
   |-- Validator
   |-- SecretScanner
   |-- GitOperations
   `-- ScmProvider
        |
        v
project-dashboard persistence
```

`AttemptRunner` owns the idempotent attempt lifecycle:

```text
prepare worktree → invoke backend → inspect changes → validate
→ secret scan → commit → push → create/recover PR → persist result
```

`ExecutionBackend` owns model-specific execution only: given a prepared,
isolated worktree, produce code changes. All reconciliation of worktrees,
branches, pushes, and PRs belongs to `AttemptRunner`.

### agent-service

Potentially reused later for local model pool routing, notifications, and
approvals. Not a Phase 1 dependency. Revisit after the local-only pilot: adopt
it only if it cleanly removes duplication from the conductor's local path.

### Forgejo

The writable SCM boundary. Required flow for a write-enabled repository:

1. create work branch from the default branch
2. execute changes in an isolated worktree
3. validate (tests + secret-diff scan)
4. commit
5. push branch
6. create pull request (after checking none exists for the branch)
7. persist PR metadata
8. task becomes review-ready

---

## Data Model Extensions

### Projects

New fields:

- `execution_lane` — portfolio lane (factory-improvement, revenue, creative)
- `priority` — ranks across projects; never duplicates task priority
- `automation_enabled` — hard gate for autonomous dispatch, default `false`
- `max_concurrent_tasks` — default `1`
- `default_workflow_profile`

Existing projects remain non-autonomous after migration.

### Repositories

New fields:

- `scm_provider` — `forgejo` | `github` | `local` | `other`
- `canonical_remote` — the authoritative remote; `url` remains as a
  compatibility alias until callers migrate
- `default_branch` (exists)
- `write_enabled` — default `false`
- `pr_enabled` — default `false`
- `auto_deploy_on_main` — cached advisory flag for display only; the control
  plane owns this fact and no safety decision reads this column
- `bot_credential_ref` — reference (not value) to the repo-scoped token in
  secret tooling

Dropped from v1: `requires_human_merge` (invariant, not a column),
`migration_status` (derivable; six-state enums rot).

Dispatch eligibility rule — all must hold:

- `scm_provider = 'forgejo'` and `canonical_remote` points at Forgejo.
  Dual-remote repositories where GitHub is canonical are ineligible: a bot
  branch on Forgejo that GitHub never sees is silent divergence.
- `write_enabled` and `pr_enabled` are true
- project `automation_enabled` is true
- branch protection verified present via Forgejo API
- deploy hook audited if the repository has deploy automation
- no other active attempt on this repository

### Tasks

New fields:

- `workflow_profile`
- `execution_complexity`
- `risk`
- `selected_repository_id`

`tasks.status` (`open`, `in_progress`, `in_review`, `blocked`, `done`,
`archived`) remains the single task state machine. No `execution_disposition`
column. Derived states, computed by the portfolio read model:

- **review-ready** = `status = in_review` AND latest attempt has persisted PR
  metadata
- **human-required** = `status = blocked` AND latest attempt is `blocked`
  with `failure_category` ∈ {`human_required`, `policy_blocked`,
  `budget_exhausted`}

### task_execution_attempts (new table)

Identity and lineage:

- `id`, `task_id`, `project_id`, `repository_id`
- `parent_attempt_id` — escalation chains
- `run_id` — link to existing dashboard runs
- `attempt_number`
- `idempotency_key` — deterministic (e.g. `task_id:attempt_number`); every
  external side effect (branch name, PR lookup) derives from it

Claim and liveness (crash recovery depends on these):

- `claimed_by` — conductor instance identity
- `lease_expires_at`, `heartbeat_at`

Decision:

- `backend` — `local` | `claude` (`codex` reserved, post-MVP)
- `model`
- `selection_reason`, `selection_inputs_json`
- `resolved_policy_json` — snapshot of the merged
  global → project → repository policy that governed this decision, so it stays
  explainable after policy tables change

Execution and outcome:

- `status` — `claimed` | `running` | `succeeded` | `failed` | `cancelled` |
  `escalated` | `blocked`. `failed` means the backend actually tried and did
  not succeed (`validation_failed`, `model_timeout`, `capability_gap`, …).
  `blocked` covers non-execution outcomes (`human_required`,
  `policy_blocked`, `budget_exhausted`) so they never distort execution
  failure metrics or trip failure breakers. v1's `review_ready` and
  `human_required` statuses are removed: the first is task-level and derived,
  the second is `blocked` + `failure_category = human_required`.
- `failure_category`
- `capability_assessment_json`
- `token_input`, `token_output`, `cost_estimate`
- `branch`, `commit_sha`
- `validation_status`, `validation_output_json` — validation is part of the
  attempt, never a sibling attempt
- `pr_provider`, `pr_id`, `pr_url`
- `started_at`, `completed_at`, `created_at`, `updated_at`

Corrected escalation example:

```text
Task 184
  Attempt 1: backend=local   → failed (capability_gap), validation included
  Attempt 2: backend=claude  → succeeded, parent_attempt_id = attempt 1
```

### repository_execution_leases (new table)

- `repository_id` (unique)
- `lease_owner`
- `lease_expires_at`

Structural enforcement of one active attempt per repository — distinct from
attempt liveness — and the coordination point for recovery, branch cleanup,
repository refresh, and future rebase/update operations. Acquired through the
dashboard API alongside the attempt claim; released on attempt completion or
lease expiry.

### Artifacts

Add nullable `attempt_id` now. It is a cheap FK and backfilling attempt
association later ranges from painful to impossible. No interim encoding in
`kind`/`workflow_id`.

---

## Provider-Neutral Execution Backend

```ts
export interface ExecutionBackend {
  readonly id: "local" | "claude" | "codex";

  // Advisory only. A TOCTOU race with execute() is unavoidable, so
  // model_unavailable must be a handled failure category regardless.
  isAvailable(input: BackendAvailabilityInput): Promise<BackendAvailability>;

  // Model execution only: given a prepared, isolated worktree, produce code
  // changes. No git operations, no push, no PR, no SCM credential.
  // Cancellable via the signal; must enforce the token/cost cap in the
  // request. Lifecycle idempotency is owned by AttemptRunner, which
  // reconciles observable state (worktree, branch, PR) keyed by the
  // attempt's idempotency_key.
  execute(input: ExecutionRequest, signal: AbortSignal): Promise<ExecutionResult>;
}
```

`ExecutionRequest` carries: attempt id, task, project, repository context,
workflow profile, worktree path, allowed files, validation commands (the
backend may run them iteratively while working; the authoritative validation
pass belongs to `AttemptRunner`), context artifacts, resolved policy, and a
token/cost cap the backend must enforce. Branch naming and all git/SCM side
effects are `AttemptRunner`'s, derived from the idempotency key.

`ExecutionResult` carries: status, model, summary, changed files, failure
category, token/cost actuals, artifacts.

MVP implementations: `LocalExecutionBackend` (wraps the existing local persona
workflow) and `ClaudeExecutionBackend`. `CodexExecutionBackend` is deferred —
the interface slot is the extension point.

Provider-specific prompting, CLI invocation, and result parsing stay inside
each implementation. The conductor owns policy; the backend only executes.

---

## Execution Policy

Decision timing:

- **Disposition** (local / local-then-premium / direct-premium / human) is
  decided **pre-execution**, preferably at authoring time via the existing
  `POST /plans/evaluate` — the plan evaluator's complexity and capability
  verdicts are the routing input, not a new parallel system.
- **Failure classification** is decided **post-attempt**.
- **Escalation eligibility** is pure policy.

Do not over-invest in pre-execution prediction for mid-tier tasks: a cheap
local attempt is often the most honest complexity probe.

Routing stays simple to avoid a brittle rules engine: a small fixed input set
(complexity, capability tier, benchmark evidence, resolved policy, prior
attempts) feeding simple thresholds. Every decision persists its inputs,
chosen backend, reason, and rejected alternatives. When routing is wrong, tune
thresholds or fix capability data — never add an exceptions list.

Hard rules:

- project automation disabled → human-required
- repository ineligible (see dispatch rule) → human-required
- workflow profile `failure_policy = block` → no automatic escalation
- plan evaluation says premium-delegate and premium is allowed → premium;
  otherwise human-required
- local failure with an escalation-eligible category and premium allowed →
  child premium attempt
- premium exhausted or disabled → human-required

### Premium-use policy

Inheritance: `global defaults → project override → repository override`,
resolved as a static precedence merge at dispatch time, with the merged result
snapshotted to `resolved_policy_json` on the attempt. No dynamic rules engine.
No task-level override in the MVP.

Policy fields: premium enabled, preferred premium backend, direct-premium
threshold, max attempts per task, per-attempt token/cost cap.

### Failure taxonomy

Escalation-eligible: `validation_failed`, `capability_gap`,
`context_too_large`, `patch_apply_failed`, `model_timeout`.

Retry-later (same backend): `model_unavailable`.

Blocking (attempt status `blocked`; task waits on a human or a policy/budget
change, and none of these count toward failure metrics or breakers):
`policy_blocked`, `budget_exhausted`, `human_required`.

Guardrail (attempt status `failed`): `safety_blocked` — a sandbox or guardrail
tripped during execution; distinct from `policy_blocked`, which prevents
execution from starting.

Task-blocking, needs refresh: `merge_conflict` (branch stale against the
default branch at push/PR time — distinct from `git_push_failed`).

Infrastructure alerts, not routing signals: `git_dirty`, `git_push_failed`,
`scm_pr_failed`. These page the operator; they never escalate the task to a
more expensive model.

Catch-all: `unknown`.

---

## Budgets and Circuit Breakers

- **Per-attempt cap:** token/cost ceiling passed in `ExecutionRequest`,
  enforced by the backend; breach → `budget_exhausted`.
- **Global daily premium cap:** conductor-level circuit breaker; when spent,
  all premium dispatch halts until reset. Local dispatch may continue.
- **Per-repo failure breaker:** N consecutive failed attempts on one
  repository pauses dispatch to it and surfaces an alert.
- **Global failure-rate breaker:** portfolio-wide failure rate above threshold
  halts all dispatch.
- **Kill switch:** manual global halt, checked before every claim.

Actuals are recorded per attempt; per-project cost allocation is deferred
(global + per-attempt suffices for a single operator).

---

## Isolation and Sandboxing

Principle: **the coding process has less privilege than the orchestration
process.** A tool-holding agent with shell access can inspect its
environment, so nothing the agent doesn't need may be there.

MVP-minimum (in force from the first local pilot — the pilot proves the
production-shaped isolation model):

- attempts execute as a **dedicated non-privileged user** with its own
  checkout root — no access to operator SSH keys, inventory, or `.env` files
- **the coding process holds no SCM credential.** The repo-scoped Forgejo
  token is held only by the trusted `AttemptRunner` git/SCM helper, which
  runs outside the coding agent's environment; the backend can modify the
  worktree but cannot push
- for premium attempts, the provider API key is injected only into the
  provider CLI process — the one credential the coding process necessarily
  carries. It is provider-scoped: it can spend budget but cannot touch SCM.
  Nothing is written to the worktree
- **fresh worktree per attempt**, deleted on completion; never a shared
  working tree (a prior parallel-agent run on a shared tree has already
  demonstrated this failure mode)
- git wrapper strips `--force` and restricts pushes to the attempt's branch
- **secret-diff scan** (e.g. gitleaks) as a mandatory validation step before
  any push

End state: container per attempt with a network egress allowlist (Forgejo +
provider API only). Command blocklists are explicitly rejected — the sandbox
boundary constrains the shell, not string matching.

---

## Concurrency and Recovery

- **Claiming:** the conductor requests a claim through the dashboard API
  (`POST /execution/claims`, carrying its eligibility filter);
  `project-dashboard` performs the atomic mutation
  (`SELECT … FOR UPDATE SKIP LOCKED` inside its own transaction) and returns
  the claimed attempt. Heartbeats and lease renewal likewise go through the
  API. The conductor decides eligibility and policy; the dashboard owns
  durable atomic state mutation — the conductor never touches dashboard
  database internals.
- **Repository exclusivity:** the repository execution lease (see data model)
  is acquired with the claim and structurally enforces one active attempt per
  repository, independent of dispatcher behavior.
- **Caps:** global concurrent attempts (start at 2–3), exactly 1 active
  attempt per repository (via the repository lease), per-project cap from
  `max_concurrent_tasks`.
- **Crash recovery:** on startup and on a schedule, sweep attempts with
  expired leases; reconcile each against observable reality — worktree
  present? branch on remote? PR exists (looked up by branch via
  `ScmProvider`)? — then either resume metadata persistence or mark the
  attempt `failed` with an accurate category, and release the repository
  lease either way. Duplicate side effects are
  prevented by deriving branch names and PR lookups from the idempotency key.
- **Stuck-attempt detector:** lease expired with no terminal status raises an
  alert.

---

## Forgejo Workflow

```ts
export interface ScmProvider {
  readonly id: "forgejo" | "github" | "local" | "other";

  createPullRequest(input: CreatePullRequestInput): Promise<PullRequestResult>;

  // Required for idempotent recovery: crash after PR creation but before
  // metadata persistence must not create a duplicate PR.
  findPullRequestByBranch(input: FindPullRequestInput): Promise<PullRequestResult | null>;

  getPullRequest(input: GetPullRequestInput): Promise<PullRequestResult>;
}
```

This interface must never gain a merge method.

The Forgejo implementation parses the canonical remote into owner/repo, calls
Forgejo-compatible PR APIs with the repo-scoped token, checks for an existing
PR by branch before creating, returns PR id/URL/branches/status, and never
logs tokens or secret-bearing request details. Branch pushes use plain git
over the scoped token; push is not part of this interface.

Audit record per SCM operation: attempt id, token identity (not value), remote
URL, ref, before/after commit SHAs, API response summary, timestamp — enough
to correlate with Forgejo's own audit log.

---

## Portfolio Views

One endpoint:

```
GET /portfolio?state=running|queued|blocked|awaiting_review|recently_completed
```

(no `state` returns the full portfolio summary). Six separate routes for six
filters of the same query is API surface without value.

Awaiting-review rows include: project, task, backend, model, escalation reason
if any, branch, Forgejo PR id and URL, validation status, artifact summaries,
and the human action required. The dashboard makes the boundary obvious:
review and merge happen in Forgejo, not in the worker.

---

## Operational Gates

Metrics required **before** enabling parallel streams:

- attempt success rate by backend
- escalation rate and escalation success rate
- validation failure rate
- cost and tokens per attempt; daily premium spend
- queue age (oldest eligible unclaimed task)
- stuck-attempt count

Dispatch stops automatically on: per-repo breaker, global failure-rate
breaker, daily premium cap, kill switch.

---

## Implementation Phases

Reordered from v1: the end-to-end pilot moves before any premium backend, and
Codex drops out of the MVP.

### Phase 1 — Schema and Persistence

- extend `projects` and `repositories` (fields above; safe defaults:
  everything off)
- add task execution fields
- add `task_execution_attempts` **including claim/lease/idempotency columns**
- add `repository_execution_leases`
- add nullable `artifacts.attempt_id`
- attempt CRUD APIs; `GET /portfolio` read model
- claim/heartbeat/release APIs (`POST /execution/claims`, …) — the dashboard
  owns the atomic claim transaction so the conductor never touches its
  database internals
- tests, docs; existing API compatibility preserved

Must not: change dispatch behavior, invoke any premium provider, touch
Forgejo, push commits, enable automation anywhere.

### Phase 2 — Enforcement Setup

- provision branch protection on candidate pilot repositories
- provision repo-scoped bot tokens; wire `bot_credential_ref`
- audit deploy hooks on any candidate with deploy automation
- conductor-side protection-verification check

This phase is deliberately before any code that writes to SCM.

### Phase 3A — AttemptRunner and Isolation

- introduce `AttemptRunner`, `WorktreeManager`, and the trusted
  `GitOperations`/SCM helpers (the only holders of the Forgejo token)
- dedicated non-privileged execution identity, fresh worktrees, git wrapper,
  secret-diff scan
- attempt and repository lease coordination against the dashboard claims API

### Phase 3B — LocalExecutionBackend

- introduce `ExecutionBackend`; wrap the existing local persona workflow as
  `LocalExecutionBackend` — model execution only, no git, no SCM credential

### Phase 3C — Forgejo Adapter

- implement the Forgejo `ScmProvider` (create + find + get PR) with
  recovery/idempotency behavior
- unit-test selection and recovery logic with no premium calls

### Phase 4 — Execution Policy and Attempt Lifecycle

- policy resolution (global → project → repo) with persisted snapshots
- claim/lease dispatch loop, heartbeats, crash-recovery sweep
- attempt lifecycle wiring: create → run → validate → classify → persist
- circuit breakers and kill switch

### Phase 5 — Local-Only End-to-End Pilot

The smallest credible slice that proves the architecture: one manually
authored task, one repository (AssetForge or a scratch repo), hardwired
policy, claim through the dashboard API, fresh worktree under the dedicated
execution user, `LocalExecutionBackend`, validation, secret scan, trusted
branch push (`AttemptRunner` holds the token), Forgejo PR, review-ready in
the dashboard. No premium, no escalation. The pilot runs the
production-shaped isolation model, not a shortcut.

Exit criteria: no manual coding intervention; no merge, no default-branch
push, no secret mutation, no deploy; recovery sweep tested by killing the
conductor mid-attempt and observing correct reconciliation.

### Phase 6 — Claude Backend and Escalation

- `ClaudeExecutionBackend` with per-attempt caps and cancellation
- escalation: child attempts via `parent_attempt_id`, driven by the failure
  taxonomy
- daily premium spend cap live before the first real premium attempt

### Phase 7 — Premium Pilot and Portfolio Rollout

- one safe AssetForge task through local-then-premium escalation end to end
- register the three streams (HomeOps / factory, Arremate / revenue,
  AssetForge / creative) with automation enabled per-task, then per-project,
  as confidence and metrics allow

### Post-MVP (explicitly out of scope now)

- `CodexExecutionBackend` — added when benchmark evidence exists to route
  between premium providers; until then Claude-vs-Codex routing is
  unanswerable
- task-level premium-policy overrides
- per-project cost allocation
- container-per-attempt sandboxing with egress allowlist (upgrade from the
  isolation MVP)
- `agent-service` as the conductor's local routing layer (revisit after
  Phase 5)
- **autonomous task generation** — a different risk class (the system decides
  what work exists rather than executing human-approved work); requires its
  own review brief and its own invariants before design begins

---

## Open Questions

1. Which dashboard UI surface renders the portfolio view first?

Resolved by the v2 review:

- the dedicated execution user applies from the first local pilot
- the existing `runs` model is unchanged; `task_execution_attempts.run_id` is
  the link, and the runs model changes only if implementation demonstrates a
  real problem
- the per-repo failure-breaker threshold and the daily premium cap are
  configuration, tuned from pilot evidence — operating decisions, not
  architecture decisions

---

## Conclusion

The system remains an extension of what exists, not a replacement. v2 keeps
v1's decomposition and phasing philosophy, and changes where safety is
enforced (server-side), when concurrency is designed (Phase 1), how validation
is modeled (attempt phase), and what the MVP carries (one premium backend, one
portfolio endpoint, a local-only pilot first). The post-review revision adds
the final decomposition:

```text
project-dashboard      durable state, atomic claims
task-flow-conductor    scheduling and policy
AttemptRunner          idempotent execution lifecycle (trusted, holds SCM credential)
ExecutionBackend       model-specific coding execution (least privilege)
Forgejo                protected SCM/review boundary
human                  merge/deployment approval
```

Human merge remains the only path from autonomous work to deployment — and
after v2, that is true even if every line of conductor code is wrong.
