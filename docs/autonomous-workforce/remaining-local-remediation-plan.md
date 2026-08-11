# Remaining Local Execution Remediation Plan

## Purpose

This plan captures the remaining remediation work needed to bring the new
provider-neutral local execution path back in line with the hard-won behavior
of the previous local model harness.

The recent N3.3 dogfood run proved that the local path is usable again for
well-scoped single-file tasks. It also exposed the parity gap this plan now
closes: multi-file tasks could fail when the model emitted valid full-file
rewrites for different target files across different repair rounds.

## Current Status

- Local execution is restored for scoped tasks.
- Parser-gated intake is active through `workq add`.
- Runtime file authority comes from durable `target_entries`, not task prose.
- Forgejo branch / PR execution is active.
- Repository-scoped auto-merge on validation works for the POC dashboard repo.
- Premium execution stayed disabled during the N3.3 dogfood run.
- Live conductor now receives `EXECUTION_LOCAL_MAX_ROUNDS=3`.
- R10 partial-output repair has landed.
- R11, R12, R13, R14, R16, R17, and R18 have landed.
- R19 validation checkpointing, R20 repeated no-op detection, and R22
  target-scoped import repair are implemented in `task-flow-conductor`.
- R21 baseline validation delta has been evaluated and remains deferred from
  the local backend; the existing QA validation path is still the delta-aware
  mechanism for broader repository validation.

## R10 - Partial-Output Repair

Priority: P0

Status: implemented.

Goal: recover valid file rewrites across rounds instead of discarding them.

Problem observed: task 172 required changes to `src/routes/ui.ts` and
`tests/ui-route.test.ts`. The local model produced one valid target file in one
round and the other valid target file in another round, but the backend failed
because each individual response did not contain every required file.

Deliverables:

- Persist parsed valid file blocks per repair round.
- Accumulate accepted rewrites by target file.
- If round 1 outputs file A and round 2 outputs file B, combine A+B before
  apply.
- Use newest-valid-wins semantics per target file: if a later round emits a
  valid rewrite for an already-banked target, replace the prior rewrite. This
  lets the model re-emit file A while producing file B when cross-file
  signatures, imports, or call sites need to be brought back into agreement.
- Apply once, and only once, after the accumulated rewrite ledger covers every
  required target. Validation then runs against the merged file set, not a
  per-round partial application.
- Re-prompt only for missing or invalid target files.
- When validation fails after applying the merged set, feed diagnostics back
  into the next round and allow newest-valid rewrites to replace banked files.
- If rounds are exhausted with an incomplete ledger, fail with the missing
  target list in the attempt summary.
- Never carry forward edits for reference files.
- Add artifact kind `local_accumulated_rewrites`.
- Use task 172's persisted artifacts as the replay fixture for this failure
  class; the test should be derived from the actual transcript pattern where
  each round supplied a different required file.
- Add tests proving a multi-file task succeeds when each round supplies a
  different required file.

Acceptance:

- A two-target local task succeeds when round 1 returns only target A and round
  2 returns only target B.
- A later valid rewrite for target A replaces the earlier banked target A
  rewrite.
- A later invalid rewrite for target A does not corrupt an earlier accepted
  rewrite unless explicitly replaced by a valid target A rewrite.
- Apply is invoked only after the ledger covers every required target.
- Validation runs against the merged set and can trigger another repair round
  for inconsistent A+B changes.
- Exhaustion with missing targets records `local_accumulated_rewrites` and
  names the missing target files in the failure summary.
- Reference-file rewrites are still rejected.
- Existing single-file local backend tests continue to pass.

## R11 - Legacy Harness Parity Audit

Priority: P0

Status: implemented.

Goal: stop rediscovering old local-model lessons.

Deliverables:

- Inventory the previous local execution harness behavior.
- Explicitly re-evaluate the originally deferred old-harness behaviors,
  especially the info-request loop and stepwise implementation stages, against
  their stated re-entry conditions.
- Map each old-harness feature to the new execution path:
  - present
  - partial
  - missing
  - obsolete
- Identify deterministic gates still absent from the new path.
- Identify repair-cycle behaviors that are weaker than the old path.
- Convert missing high-value behavior into tracked remediation tasks.

Acceptance:

- A parity matrix exists in docs.
- Every missing P0/P1 behavior has a follow-up task or an explicit rationale
  for not porting it.

## R12 - Task-Shaping Guardrails

Priority: P1

Status: implemented.

Goal: prevent known-bad task shapes from entering local execution silently.

Deliverables:

- Extend plan evaluation or intake checks to flag risky local-task shapes.
- Detect local tasks that combine route, test, server registration, schema, or
  migration edits in one unit.
- Derive every detection signal from structured task metadata such as
  `target_entries`, target count, and path-class classification. Do not inspect
  task prose to decide execution shape.
- Recommend split sequencing when the local backend is selected.
- Keep checks advisory for premium backends.
- Fail closed only when a task violates the directed-task contract.

Acceptance:

- `POST /plans/evaluate` or equivalent intake tooling warns when a local task
  is likely too broad.
- Existing valid single-file tasks are not blocked.
- Premium-capable tasks are not incorrectly rejected for local-only shaping
  concerns.

## R13 - Repair Prompt Improvements

Priority: P1

Status: implemented.

Goal: make local repair rounds more targeted.

Deliverables:

- Include parser errors in compact form.
- Include validation diagnostics in compact form.
- Refine the diagnostics language used by R10 repair prompts.
- Strengthen instructions for validation-repair cases without duplicating
  R10's missing-file banking logic.

Acceptance:

- Repair prompts for validation failures name the failing target files and
  concise diagnostics.
- Tests cover validation repair prompt generation.

## R14 - Validation Repair Coverage

Priority: P2

Status: implemented for unused imports, duplicate imports, and target-scoped
relative import-path repair.

Goal: broaden deterministic repair without introducing risky semantic rewrites.

Current restored behavior:

- Unused-import cleanup is deterministic and scoped to eligible target files.

Deliverables:

- Identify other safe deterministic cleanups.
- Consider low-risk fixes such as duplicate imports or simple formatting-only
  failures.
- Avoid semantic auto-fixes unless proven with tests.

Acceptance:

- Any added cleanup has focused tests.
- Cleanup never touches reference files.
- Cleanup records artifacts describing what changed.

## R15 - Runtime Config Hardening

Priority: P1

Status: implemented for the Compose/config surface and startup posture logging;
live deployment remains owned by GitOps.

Goal: avoid hot-patch drift.

Problem observed: `EXECUTION_LOCAL_MAX_ROUNDS` existed in code but was not
passed through the live Compose environment until hot-patched.

The Compose service environment is only one layer. The value must also reach
Compose through the gateway workload environment JSON/materialization path.
Both layers must be checked because prior config incidents happened in the
workload environment layer, not only in the Compose allowlist.

Deliverables:

- Ensure execution knobs are passed through Compose:
  - `EXECUTION_LOCAL_MAX_ROUNDS`
  - `EXECUTION_LOCAL_TIMEOUT_MS`
  - local model settings
  - breaker thresholds
  - premium policy settings
- Add a deterministic allowlist check: extract `process.env.EXECUTION_*`
  references from `src/config.ts` and assert each intended runtime knob appears
  in `docker-compose.yml`, with documented exceptions.
- Document and verify the gateway workload environment carries the intended
  execution knobs into Compose materialization.
- Add startup logging for non-secret execution posture.

Acceptance:

- A clean redeploy preserves the intended local repair-round count through both
  the workload environment and Compose allowlist layers.
- Startup logs show project scope, premium state, local rounds, and breaker
  posture without printing secrets.
- The startup posture log is the verification point for the effective local
  round count.
- Compose config coverage is tested or otherwise checked in CI/local
  validation.

## R16 - Dashboard POC Cleanup

Priority: P2

Status: implemented for the initial POC cleanup; further dashboard UX work
should be driven by new product tasks, not this remediation track.

Goal: make `/ui` useful enough to operate without confusion.

Recent cleanup completed:

- Filtered the POC view to project 10.
- Hid action buttons outside `awaiting_review`.
- Archived superseded project-10 scaffold failures.

Remaining deliverables:

- Add a project selector or current automation project filter.
- Add compact counts per section.
- Add clearer empty states.
- Show backend, model, validation status, and PR only where relevant.
- Avoid rendering old unrelated projects by default.

Acceptance:

- Default `/ui` is not a historical backlog dump.
- Actions appear only for rows where the action is valid.
- A user can tell what work is running, blocked, awaiting review, or recently
  completed without reading raw task history.

## R17 - Auto-Merge Policy Visibility

Priority: P2

Status: implemented.

Goal: make hands-off behavior auditable.

Deliverables:

- Show repository `merge_policy`.
- Show whether auto-merge succeeded or degraded to human review.
- Add explicit persisted attempt fields for merge outcome rather than parsing
  free-form result text. Suggested shape: `merge_status` with values
  `not_attempted`, `merged`, `degraded`, and optional `merge_failure_category`
  / `merge_failure_detail`.
- Expose merge result in portfolio/recently completed data without exposing
  credentials.

Acceptance:

- A completed task can show "auto-merged" versus "left for human review".
- Auto-merge failures are visible in the dashboard and attempt history.
- Dashboard code does not string-mine `result` to infer merge state.
- Credential names or token values are never exposed.

## R18 - Local Token Accounting

Priority: P2

Status: implemented.

Goal: record local model token usage so routing and budgeting decisions have
real data.

Problem observed: local runs currently leave `token_input` and `token_output`
null even though attempt fields already exist and LM Studio responses can carry
usage data.

Deliverables:

- Extend the LM Studio local call path to capture usage fields when present.
- Persist local token input and output counts on execution attempts.
- Include token metadata in local backend artifacts or attempt updates without
  exposing prompts beyond the existing artifact policy.
- Keep behavior tolerant when a local provider omits usage.

Acceptance:

- A local attempt records token counts when LM Studio returns usage.
- A local attempt still succeeds when usage is unavailable.
- Token metadata is available for future task-shaping and routing policy.

## Implementation Sequence Completed

1. R15 - Runtime config hardening.
2. R10 - Partial-output repair.
3. R11 - Legacy harness parity audit.
4. R12 - Task-shaping guardrails.
5. R13 - Repair prompt improvements.
6. R18 - Local token accounting.
7. R17 - Auto-merge visibility.
8. R16 - Dashboard cleanup.
9. R14, R19, R20, and R22 - additional repair-cycle parity.

## Operating Guidance After Remediation

The local backend should prefer narrow, well-scoped, single-target tasks even
after R10 lands. The 5-for-5 round-one dogfood result on properly scoped tasks
is a better operating point than routinely relying on repair.

Multi-file tasks should be reserved for genuine coupled changes such as a route
and its focused test. Broad feature work should still be split into explicit
task sequences unless the repository policy intentionally routes it to a backend
that can handle broader edits.

The backend now preserves valid partial file rewrites across repair rounds when
multi-file work is genuinely necessary, matching the relevant lesson from the
previous local harness. That resilience is a fallback, not a reason to author
large local tasks by default.

## R21 Decision

Backend-level baseline validation delta remains deferred. Running baseline
validation inside every local attempt would execute the repository validation
commands before model work and can double the cost/time of local execution.
The local backend also cannot assume every validation command returns parseable
file diagnostics.

Current posture:

- parseable validation diagnostics are fed back into local repair prompts
- failed validation repair rounds restore the worktree before retry
- repeated no-op rewrites fail distinctly instead of burning the whole round
  budget silently
- broader delta-aware validation remains in the existing QA validation path

Re-entry condition: implement backend-level baseline subtraction only for a
repository or validation profile that proves parseable file diagnostics and
where pre-existing unrelated failures are blocking otherwise valid local
target edits.
