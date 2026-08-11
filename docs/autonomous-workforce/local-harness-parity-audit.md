# Local Harness Parity Audit

Date: 2026-08-11

## Purpose

This audit maps the proven legacy local-model implementation harness in
`task-flow-conductor` to the newer provider-neutral local execution path. The
goal is not to port every old behavior blindly. The goal is to preserve the
lessons that made the local model reliable while keeping the new directed-task
contract deterministic and provider-neutral.

## Summary

The new `LocalExecutionBackend` has restored the most important structural
lessons:

- file authority comes from durable task metadata, not editable prose
- model output is parsed as full-file rewrites, not fuzzy diffs
- reference-file rewrites are rejected
- valid partial target rewrites can now be banked across rounds
- artifacts capture prompts, outputs, parser results, and accumulated rewrites
- local execution stays behind the provider-neutral backend contract

The main remaining parity gaps are now lower-risk operating choices rather
than broken local execution mechanics:

- backend-level baseline validation delta remains deferred
- richer validation-target retry directives can still be tuned with more live
  transcripts
- repository/language-specific deterministic repairs remain plugin candidates

The old stepwise planning and information-request loop should not be restored
as default local-backend behavior. They were solutions to broad, underspecified
tasks. The current contract intentionally moves that work to planning/intake.
They should re-enter only if the directed-task contract proves too narrow for
real two-file work after R10.

## Parity Matrix

| Legacy harness behavior | Legacy location | New path status | Decision |
| --- | --- | --- | --- |
| Inject task description and plan text directly into the model prompt | `ImplementationLoopStep`, `implementationSnippets` | Present differently | The local backend builds prompts from durable task metadata and file context. Plan-artifact injection is obsolete for directed tasks unless broader planning tasks return. |
| Treat missing task descriptions as fatal rather than silently inventing work | coordinator/task extraction fixes | Present | Intake now requires the directed-task contract and structured target/reference metadata. |
| Structural corruption guard for LLM edits | `applyEditOps.ts` | Present differently | Full-file parser rejects malformed or non-target rewrites before write. The old diff-corruption recovery is no longer needed because the new path does not apply fuzzy hunks. |
| Fuzzy hunk matching for imprecise diffs | `hunkHelpers.ts` | Obsolete | Full-file rewrite output intentionally replaced diff application for local coding tasks. |
| Prefer full-file rewrite after repeated structural/type failures | `generateAttemptRetryState` | Present differently | The new path always requires full-file target blocks. |
| Roll back failed validation attempts before retry | `rollbackAttempt`, `runStage` | Present | R19 added target-file checkpoint/restore around validation-repair rounds; accepted rewrites remain ledger data until the next clean apply. |
| Bank progress across attempts | old stage commits and R10 ledger | Present | R10 added accumulated rewrite banking with newest-valid-wins semantics. |
| Re-prompt only for missing or invalid files | `buildRetryDirectives`, R10 prompt path | Partial | R10 covers missing/invalid target banking. R13 should refine validation-target diagnostics without duplicating banking logic. |
| Require next repair to touch diagnostic files | `evaluateDiagnosticFileTouchGate` | Partial | The local backend names failing files, but the old hard gate is stronger. Track as R13/R19 depending on implementation depth. |
| Repeated no-effective-change detection | `commitOrHandleNoop` | Present | R20 detects repeated no-op full-file repair output for unresolved targets and fails distinctly with artifacts. |
| Baseline typecheck delta detection | `captureBaselineTypecheck`, `evaluateTypecheckValidation` | Partial | Repository validation can fail or pass, but the new path does not yet subtract pre-existing typecheck errors in the backend. Track as R21 if broad repos expose this again. |
| Deterministic unused-import cleanup | `unusedImportRepair` | Present | Already restored for eligible target files and kept target-scoped. |
| Deterministic relative import repair | `importPathRepair` | Present | R22 reuses the legacy TS2307 relative import repair only for target files; reference files remain immutable. |
| Deterministic domain-specific Roblox API repair | `robloxApiRepair` | Missing by design | Do not port into generic local backend. Re-enter only through repository/language-specific validation plugins. |
| Luau formatting helper | `formatLuau` | Missing by design | Do not add globally. Use repo/language-specific cleanup hooks if AssetForge/Roblox work needs it. |
| Information-request loop | `informationRequest/*` | Deferred/obsolete | Directed local tasks must carry explicit target/reference context. Re-enter only if a task has valid structured metadata but context assembly cannot fit required references. |
| Stepwise implementation stages | `implementationStages`, `runStage` | Deferred/obsolete | Current authoring should split broad work before dispatch. Re-enter if coupled work repeatedly exceeds R10 repair capacity. |
| Convergence bonus attempts when errors change | `generateAttemptRetryState` | Partial | `EXECUTION_LOCAL_MAX_ROUNDS` now reaches runtime; dynamic bonus attempts are not restored. Treat as optional after R19/R20. |
| LM Studio timeout/circuit breaker | LM Studio client/config | Present | Local backend uses configured local timeout and breaker posture. R15 added startup visibility. |
| Artifact persistence for diagnosis | workflow artifacts and execution attempts | Present | R-era remediation exceeds the old path for prompt/output/parser artifacts. |
| SCM branch/PR execution | old git ops and new Forgejo path | Present | New path routes through Forgejo branch/PR workflow and project-dashboard run history. |

## Follow-Up Remediation Tasks

### R19 - Validation-Repair Checkpointing

Priority: P1

Status: implemented.

Implemented explicit checkpoint/restore semantics for validation-repair rounds in
the full-file local backend. After the accumulated rewrite set is applied and
validation fails, restore the worktree to the pre-apply checkpoint before the
next model round. Keep the accepted rewrite ledger as data, not as live
worktree mutation. The next successful merged set should apply to a clean
checkpoint and validation should run against that merged set.

Acceptance:

- A failed validation repair round does not leave edited target files in the
  worktree for the next round.
- The accumulated rewrite artifact still records the accepted rewrites.
- A later valid rewrite can replace a banked file and validate from the clean
  checkpoint.

### R20 - Repeated No-Op Detection

Priority: P1

Status: implemented.

Detect repeated model outputs that produce no material change for unresolved
targets or repeat the same failing rewrite signature. Fail with a clear
`already_resolved_or_bad_scope` style reason instead of consuming all rounds
silently.

Acceptance:

- Two repeated no-op repair rounds against unresolved diagnostics fail with a
  distinct failure category.
- The attempt summary names the repeated target files.
- The local backend persists the parser/result artifacts needed to diagnose
  the loop.

### R21 - Baseline Validation Delta

Priority: P2

Status: evaluated and deferred.

Evaluate whether the backend should subtract pre-existing validation failures
from repository validation output. This should be implemented only if the
validation command returns parseable file diagnostics for the target repo.

Decision: keep backend-level subtraction deferred. It would run repository
validation before model work and can double local attempt cost/time. The
existing QA validation path remains the delta-aware gate for broad repository
validation. Re-enter only for repositories or validation profiles that prove
parseable diagnostics and show pre-existing unrelated failures blocking valid
target edits.

Acceptance:

- New failures introduced by the attempt still fail the run.
- Pre-existing unrelated failures do not block an otherwise valid target edit.
- Unparseable validation failures remain fail-closed.

### R22 - Target-Scoped Import Repair

Priority: P2

Status: implemented.

Reuse the existing deterministic import repair where it can be safely scoped to
target files. Do not touch reference files. Record repair artifacts.

Acceptance:

- TS2307 relative import repairs only modify target files.
- Ambiguous repairs are skipped.
- Applied repairs are recorded in the run artifacts.

## Deferred Behaviors

The information-request loop and stepwise implementation stages remain
deferred. Their original purpose was to compensate for broad planning tasks and
missing model context. The current operating model deliberately pushes that
complexity into deterministic planning and queue intake.

Re-entry conditions:

- R10 plus narrow task authoring still cannot handle genuine two-file tasks
  such as route plus focused test.
- The planner can prove a task needs staged execution even after structured
  target/reference metadata is complete.
- Required reference context exceeds prompt limits even after targeted context
  assembly.

Until those conditions are met, restoring these loops would make the new local
backend less deterministic and would increase the chance of task prose or model
requests becoming an execution authority again.
