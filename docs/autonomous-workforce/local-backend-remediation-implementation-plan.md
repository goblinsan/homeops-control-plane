# Local Backend Remediation Implementation Plan

Status: R8 accepted, R9 pending real queue continuation, 2026-08-11. Companion to
`local-backend-remediation-plan.md`. This document sequences the approved
remediation into trackable work packages.

Implementation progress:

- R0 completed: evidence index written in
  `local-backend-remediation-evidence-index.md`.
- R1 completed: dashboard task file metadata and attempt-scoped artifact
  contracts are implemented with migration-idempotency coverage.
- R2 completed: conductor execution requests consume structured task metadata
  and attempt-scoped artifact filters.
- R3 completed: directed-task parsing is deterministic and `workq add` fails
  closed through `WORKQ_CONTRACT_PARSER`.
- R4 completed: shared local implementation core exists for full-file parsing,
  target/reference guards, directed context loading, and prompt construction.
- R5 completed: `LocalExecutionBackend` is a thin adapter over the shared
  full-file core and no longer uses unified diffs as the local output contract.
- R6 completed: compact validation diagnostics, targeted retry directives,
  deterministic unused-import cleanup, and repair artifacts are implemented.
- R7 completed: deterministic replay/context tests and premium-disabled
  no-escalation coverage are implemented without live model calls.
- R8 completed: live local-backend acceptance produced a validated PR, the PR
  was human-merged, the review outcome was recorded as `accepted_as_is`, and
  the kill-test recovery sweep reconciled an interrupted attempt.
- R9 remains pending against the real Workforce Self-Improvement queue. The
  isolated validation database contains only remediation-validation tasks.

Known validation note: R1-R7 targeted tests pass. The earlier
`project-dashboard` build blocker in `src/routes/ui.ts` has been fixed.

## Operating constraints

- Dispatch stays paused for the workforce self-improvement stream until the
  acceptance gate passes.
- `EXECUTION_PREMIUM_ENABLED=0` remains the remediation posture. Re-enabling
  premium is a separate post-acceptance decision.
- Do not use the current thin `LocalExecutionBackend` to implement this
  remediation. Early packages are manual or otherwise explicitly reviewed
  outside the autonomous dispatch loop; there is no automatic premium routing.
- Keep the existing execution shell: claims, leases, worktrees, validation,
  secret scanning, branch protection, PR creation, settling, breakers, and
  recovery.
- Do not revive the workflow engine as the execution path. Extract lessons
  into shared modules consumed by the new execution slice.

## Dependency graph

```text
R0 Baseline freeze
  -> R1 Dashboard durable contracts
  -> R2 Conductor API/type contracts
  -> R3 Directed task parser + workq bridge
  -> R4 Extract implementation core
  -> R5 Local backend adapter
  -> R6 Repair diagnostics and deterministic post-processors
  -> R7 Replay/no-escalation test gate
  -> R8 Live acceptance run
  -> R9 Resume N3.3 dashboard task chain
```

R1, R2, and R3 may be developed in parallel if each has contract tests, but
R5 must not start until their public interfaces are stable.

## Tracking fields

Use these fields when creating dashboard tracking tasks for this remediation.
Tracking tasks must not be claimable by the dispatcher. Put them in a separate
planning/tracking project with `automation_enabled=false`, or keep them out of
`open` status until the specific task is intentionally selected for execution.
Do not put generic R-package tracking tasks in project 10 while project 10 is
the only project in `EXECUTION_PROJECT_IDS`.

| Field | Value |
| --- | --- |
| `project` | A non-automated remediation tracking project, not project 10 |
| `selected_repository_id` | the repo being changed |
| `execution_complexity` | `medium` for contract work; `high` only for extraction/refactor tasks |
| `risk` | `medium` unless touching only docs/tests |
| `labels` | `local-backend-remediation`, plus the package id such as `R1` |

Every implementation task must name exactly one primary repository. Cross-repo
contracts are split into producer and consumer tasks with an integration gate.
Review posture is governed by the repository `merge_policy`, not by overloading
`workflow_profile`.

## Work Packages

### R0 - Baseline freeze and evidence preservation

Goal: lock the failure evidence and prevent accidental reruns while
remediation is underway.

Repository: `project-dashboard`, `task-flow-conductor`,
`homeops-control-plane`.

Deliverables:

- Confirm dispatch is paused and premium is disabled for the remediation
  stream.
- Leave tasks 159, 163, and 165-168 blocked as evidence.
- Capture the accepted remediation plan and this implementation plan in
  `homeops-control-plane`.
- Create a short evidence index naming the replay attempts and what each
  represents, without including secrets, private URLs, or topology.

Validation:

- `workq status` reports paused.
- No queued remediation task can be claimed by the current local backend.
- Evidence index references attempts 18, 20, 23, 25, 27, 28, and 32-41.

Exit gate: evidence is preserved and the operator can identify the exact
attempts that make up the replay corpus.

### R1 - Dashboard durable contracts

Goal: make project-dashboard capable of storing and retrieving the data the
remediated backend requires.

Repository: `project-dashboard`.

Deliverables:

- Add `target_files` and `reference_files` JSON fields to tasks.
- Handle the live migration view trap explicitly: `tasks_with_milestone_name`
  expands `t.*`, so migrations that add task columns must drop and recreate the
  view rather than rely on `CREATE OR REPLACE`.
- Accept and preserve those fields in task create, bulk create, patch, get,
  and portfolio paths.
- Extend artifact identity so `(project_id, task_id, kind, iteration,
  attempt_id)` is distinct.
- Add `attempt_id` filtering to task artifact GET routes.
- Update OpenAPI documentation for new task fields and artifact query
  support.
- Add migration coverage for the view drop/recreate path against an upgraded
  schema, not only a fresh database.
- Add migration coverage for replacing the artifact unique index. The new
  index should use a new durable name; avoid a permanent boot-time
  `DROP INDEX`/`CREATE INDEX IF NOT EXISTS` pair that churns the index on every
  startup.

Tests:

- Task create -> get preserves `target_files` and `reference_files`.
- Bulk create -> get preserves both fields.
- Patch -> get updates both fields.
- Portfolio output does not strip both fields.
- Two attempts on the same task can publish the same artifact kind without
  overwrite.
- Fetching artifacts with `attempt_id` returns only that attempt's artifacts.
- Migration-idempotency tests cover adding task columns when
  `tasks_with_milestone_name` already exists.

Validation:

- `npm test`

Exit gate: dashboard can round-trip every new field and uniquely retrieve
attempt artifacts.

### R2 - Conductor API and execution type contracts

Goal: teach task-flow-conductor to consume the new dashboard contracts without
changing backend behavior yet.

Repository: `task-flow-conductor`.

Deliverables:

- Extend task DTOs returned by `AttemptClient.getTask` with `target_files`
  and `reference_files`.
- Extend execution request types to carry structured target/reference file
  metadata.
- Extend `ArtifactAPI.PublishArtifactInput` with `attemptId` and send it as
  `attempt_id`.
- Extend `FetchArtifactsInput` with `attemptId`.
- Add compatibility behavior for older tasks: missing structured file fields
  causes `LocalExecutionBackend` to fail closed once R5 is active, but this
  package should not change runtime behavior yet. Premium backends are exempt
  because they can inspect the worktree directly.

Tests:

- Attempt client parses task file metadata.
- Artifact publish includes `attempt_id`.
- Artifact fetch includes `attempt_id` query filtering.
- Existing callers compile without changing behavior.

Validation:

- `npm test`

Exit gate: conductor contract changes are available to later packages and
covered by tests.

### R3 - Directed task parser and deterministic workq bridge

Goal: make task intake deterministic and fail closed before a task reaches the
backend.

Repositories: `task-flow-conductor`, then `homeops-control-plane`.

Deliverables:

- Add `src/implementation/directedTaskContract.ts` in
  `task-flow-conductor`.
- Parser accepts one TARGET entry per line:
  `- Create <path>`, `- Modify <path>`, or `- Reference <path>`.
- Parser rejects ambiguous verbs, missing paths, duplicate conflicting verbs,
  absolute paths, parent traversal, globs, directories, and empty target sets.
- Parser returns structured `target_files` and `reference_files`, preserving
  create/modify intent for target files.
- Expose a small Node CLI that reads a description file and emits JSON for
  `workq.sh`.
- Update `homeops-control-plane/scripts/workq.sh` to call
  `WORKQ_CONTRACT_PARSER`, fail closed when unavailable, remove the grep-only
  fallback, and include parsed fields in create/patch payloads.
- Update `directed-task-contract.md` with the strict TARGET grammar.
- Update `runbooks/local-workflow-queue.md` with `WORKQ_CONTRACT_PARSER`, the
  fail-closed parser requirement, and the removal of the grep-only intake
  check.

Tests:

- Parser unit tests cover valid create/modify/reference entries.
- Parser rejects ambiguous or unsafe paths.
- CLI exits non-zero for invalid task descriptions.
- `workq.sh add` refuses invalid descriptions and sends structured fields for
  valid descriptions.

Validation:

- `npm test` in `task-flow-conductor`.
- `shellcheck scripts/*.sh` in `homeops-control-plane`.

Exit gate: every new queue task carries durable structured file metadata at
intake.

### R4 - Extract shared implementation core

Goal: move the mature local implementation lessons into a shared module used
by the new execution backend.

Repository: `task-flow-conductor`.

Deliverables:

- Create `src/implementation/` as the shared implementation core.
- Extract or re-export the full-file block parsing path that already handles
  ` ```file path=... ` blocks.
- Extract prompt-building lineage from the legacy lead-engineer implementation
  prompt, preserving the full-file rewrite contract and Changed Files list.
- Extract/adapt plan key-file guard behavior to structured
  `target_files`/`reference_files`.
- Extract/adapt context assembly so structured files load first at full
  fidelity, then inventory and remaining budget.
- Keep legacy workflow imports pointed at the shared modules where practical,
  so there is one source of truth during transition.

Tests:

- Full-file blocks convert to edit operations without unified-diff hunks.
- Required target files must be present in output or produce a guard failure.
- Reference files are included in prompt context but rejected if modified.
- Target files are loaded before repo-scan inventory.
- Missing modify/reference files fail before any model call.
- Oversized target files fail before any model call.

Validation:

- `npm test`

Exit gate: core implementation behavior is available independently of
`LocalExecutionBackend`.

### R5 - Replace LocalExecutionBackend internals

Goal: keep the provider-neutral backend interface while replacing the thin
diff-based local implementation with the extracted core.

Repository: `task-flow-conductor`.

Deliverables:

- Rewrite `LocalExecutionBackend` as a thin adapter over the shared
  implementation core.
- Remove the unified-diff-only prompt as the local output contract.
- Use structured `target_files` and `reference_files`; fail closed if missing.
  This fail-closed requirement applies to `LocalExecutionBackend` only; premium
  backends are exempt.
- Preserve model resolution and LM Studio call behavior.
- Apply full-file edit operations through the existing `applyEditOps` path.
- Record backend selection reason, prompt, model output, parser result,
  context guard result, and validation diagnostics as attempt artifacts.
- Ensure validation-failed attempts still persist model metadata when the
  backend call succeeded.

Tests:

- Local backend sends full-file prompt instructions.
- Local backend does not ask for unified diffs.
- Local backend refuses missing structured file metadata.
- Successful full-file output changes the expected files.
- Validation failure persists model metadata and artifacts.
- Failed parser/application paths preserve raw response artifacts.

Validation:

- `npm test`

Exit gate: local backend no longer uses the fragile diff-contract path.

### R6 - Repair loop diagnostics and deterministic post-processors

Goal: restore the feedback and zero-token deterministic fixes that made local
execution reliable.

Repository: `task-flow-conductor`.

Deliverables:

- Capture compact validation diagnostics for retry rounds.
- Port retry directives for common TypeScript/import/export failure classes.
- Port the deterministic unused-import cleanup where it is already proven.
- Ensure repair rounds keep full-file output as the only local contract.
- Persist every repair round prompt/response/diagnostic artifact.

Tests:

- Validation output is compacted before entering the next prompt.
- Missing-export or import-related diagnostics produce targeted retry
  directives.
- Deterministic cleanup runs only on eligible files and never edits reference
  files.
- Repair artifacts are associated with the correct attempt and round.

Validation:

- `npm test`

Exit gate: failed validation produces useful, bounded repair input instead of
opaque retries.

### R7 - Replay corpus and no-escalation gate

Goal: prove the remediated path fixes the recorded failure class before any
live dogfood work resumes.

Repository: `task-flow-conductor`, with dashboard fixtures as needed.

Deliverables:

- Build reconstructed replay fixtures for attempts 18, 20, 23, 25, 27, 28,
  and 32-41. These attempts do not have persisted prompts or model outputs;
  the fixtures are derived from task metadata, repository state, validation
  output, and failure categories.
- Include task 164 as the positive-control new-file case.
- Include the existing-file `src/server.ts` case from tasks 165-168 as the
  primary regression fixture.
- Split replay coverage into three layers:
  deterministic repo-state/task-metadata fixtures proving context assembly
  includes targets and references; synthetic or dependency-injected model
  responses proving full-file output applies cleanly and old diff-shaped output
  is no longer a supported local contract; and optional live-model replay only
  through a pilot/e2e harness outside the hermetic test suite.
- Add a no-escalation regression test showing premium-disabled local failures
  do not create Claude child attempts.
- Add a context-guarantee fixture shaped like `project-dashboard` where
  `src/server.ts` would be missed by scan order unless prioritized.

Tests:

- Replay fixtures pass through parser/context/application paths without hunk
  mismatch failures where the model content is otherwise usable.
- Context guarantee proves target/reference files are in prompt context.
- Premium-disabled local failure creates no premium child attempt.
- `npm test` never calls LM Studio or any other live model endpoint.

Validation:

- `npm test`

Exit gate: replay suite passes and premium quarantine is enforced by tests.

### R8 - Live acceptance run

Goal: prove the system can complete the remediated local workflow end to end
on the real dogfood task shape.

Repositories: `project-dashboard`, `task-flow-conductor`,
`homeops-control-plane`.

Deliverables:

- Queue a fresh remediation-validation task equivalent to the task-159 chain:
  create/serve `ui.ts`, wire `server.ts`, and pass project-dashboard tests.
- Keep original tasks 159/163/165-168 blocked as historical evidence.
- Run one local attempt with dispatch enabled only for the remediation
  validation project/repository.
- Validate PR creation, branch safety, test output, artifacts, and review
  readiness.
- Kill-test the conductor mid-attempt only after the normal acceptance run
  succeeds once.

Validation:

- project-dashboard task claimed: passed.
- local backend selected with recorded reason: passed.
- implementation changes applied: passed.
- validation passes: passed.
- Forgejo branch and PR are created: passed.
- task reaches review-ready state: passed.
- prompt/response/diagnostic artifacts are visible and filtered by attempt:
  passed.
- no autonomous merge, no direct push to main, no premium child attempt:
  passed.
- no non-acceptance tracking task was claimed while dispatch was enabled for
  the acceptance run: passed in the isolated validation project.
- kill-test: passed. A mid-attempt conductor `SIGKILL` left an expired
  running attempt; restart recovery swept it to failed, released the task
  claim, and found no PR for the interrupted attempt.

Exit gate: complete. The operator reviewed and merged the validated PR, then
recorded the review outcome with `workq review`.

### R9 - Resume N3.3 dashboard task chain

Goal: resume the original workforce self-improvement loop only after the
local backend has re-earned trust.

Repository: `project-dashboard`.

Deliverables:

- Review and merge the accepted acceptance-run PR.
- Mark the fresh validation task accepted through `workq review`.
- Recreate the N3.3 dashboard UI tasks one at a time through `workq add` using
  the new directed TARGET grammar. Do not reopen old-format tasks 160-162;
  reopening bypasses intake and leaves them without structured file metadata.
- Run only one successor after its predecessor PR is merged.

Validation:

- Each task produces one PR.
- Each PR is reviewed by a human before merge.
- Each review outcome is recorded.
- No task edits a file created only on an unmerged branch.

Exit gate: N3.3 proceeds through the intended deterministic queue loop.

Note: the R8 validation database does not contain project 10 or the original
N3.3 queue. R9 must be run against the real dashboard queue/source of record,
not by reopening the isolated validation tasks.

## Suggested dashboard task sequence

Use these as task titles or milestones. Each should be one PR unless review
finds a reason to split further.

| Order | Package | Primary repo | Suggested task title |
| --- | --- | --- | --- |
| 1 | R0 | homeops-control-plane | Preserve local backend remediation evidence |
| 2 | R1 | project-dashboard | Add per-attempt artifact identity and retrieval |
| 3 | R1 | project-dashboard | Add task target/reference file fields |
| 4 | R2 | task-flow-conductor | Consume dashboard artifact attempt contract |
| 5 | R2 | task-flow-conductor | Load task target/reference fields for execution |
| 6 | R3 | task-flow-conductor | Add DirectedTaskContract parser and CLI |
| 7 | R3 | homeops-control-plane | Wire workq add to the contract parser |
| 8 | R4 | task-flow-conductor | Extract full-file implementation parser/core |
| 9 | R4 | task-flow-conductor | Add structured context assembler and guards |
| 10 | R5 | task-flow-conductor | Replace LocalExecutionBackend diff prompt path |
| 11 | R6 | task-flow-conductor | Restore validation repair diagnostics |
| 12 | R7 | task-flow-conductor | Add replay corpus and no-escalation tests |
| 13 | R8 | project-dashboard | Run local backend acceptance task |
| 14 | R9 | project-dashboard | Resume N3.3 dashboard UI task chain |

## Stop conditions

Pause implementation and return to review if any of these happen:

- A proposed implementation keeps unified diffs as a local fallback.
- Any backend reads file lists from task prose at execution time.
- Artifact storage cannot distinguish attempts for the same task/kind.
- Premium escalation occurs during remediation validation.
- A reference file is modified by local execution.
- A target file is missing from prompt context and the model is still called.
- A replay fixture fails in the same class it was meant to prevent.

## Completion definition

The remediation is complete when:

1. R1-R7 tests pass.
2. R8 produces a validated local PR with per-attempt artifacts.
3. The operator records the review outcome for that PR.
4. Dispatch remains scoped and premium remains disabled until explicitly
   re-enabled.
5. The original N3.3 queue can resume one task at a time without relying on
   the old thin local backend path.
