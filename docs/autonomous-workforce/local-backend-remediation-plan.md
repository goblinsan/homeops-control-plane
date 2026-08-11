# Local Execution Remediation Plan

Status: draft for review, 2026-08-10. No implementation begins until this
plan is approved.

## What happened, plainly

Plan-v2 built a clean execution slice (dispatcher → AttemptRunner →
ExecutionBackend) and its Phase 3B local backend re-implemented model
execution from scratch: repo-scan-ordered context, a unified-diff output
contract, and a thin repair loop. It reused low-level legacy modules
(LM Studio client, edit application) but bypassed the mature implementation
harness — the full-file rewrite contract, plan key-file guard, targeted
context selection, validation diagnostics, and retry directives that a year
of hardening produced. The correct move was to **extract the mature
implementation core and consume it from the new slice**; instead the slice
re-learned, in production, lessons the harness had already paid for. That
design decision and its review were the plan author's miss, not drift.

Verified failure mechanics (task-flow-conductor, `src/execution/localBackend.ts`):

- Context assembly takes files **in repo-scan order** until a 64 KB budget
  is full, with no prioritization of the task's target files. Small repos
  masked this (everything fit); on project-dashboard the edit targets were
  likely absent from context while the prompt demanded character-exact
  hunks against them.
- The output contract is unified diffs with exact hunk context — the
  precise fragility the legacy harness eliminated. Evidence: on the pilot
  sandbox the target file **was** fully in context and the local model
  still produced mismatched hunks, repeatedly; the legacy lead-engineer
  contract states full-file rewrite blocks are required *because* diffs
  "are fragile and prone to context mismatch errors".

Failure corpus for replay: pilot-sandbox tasks 155/157 (attempts 18, 20,
23, 25 — `patch_apply_failed` with target in context), project-dashboard
task 159 (attempt 27 `validation_failed`, attempt 28 `patch_apply_failed`).

## Principles

1. **Refactor, don't reinvent.** Where a mature mechanism exists in the
   legacy harness, extract it into a shared module and consume it — do not
   write a parallel version.
2. **The outer slice stays.** Claims/leases, worktree isolation, validation
   gates, secret scanning, protection verification, PR creation, settling,
   budgets, breakers, recovery are new capabilities the legacy engine never
   had, and they are proven. Remediation is confined to what happens
   between "worktree ready" and "changes on disk".
3. **Every ported mechanism carries a test**, including replay tests built
   from the recorded failure corpus above.
4. **Failures must leave evidence.** Raw prompt and model output persist as
   attempt artifacts; no future investigation should require forensics.

## Inventory of legacy protections and their fates

| # | Mechanism | Where it lives today | Fate | Rationale |
| --- | --- | --- | --- | --- |
| 1 | Full-file rewrite output contract (never diffs) | `personas.ts` lead-engineer; `workflows/prompts/lead-engineer-implementation.txt` | **Port — becomes the local output contract** | The central hard-won lesson; directly explains 6 of 6 recorded local failures |
| 2 | `implementation_prefer_full_file` recovery escalation | `lead-engineer-implementation.txt` (~L94) | **Subsumed by #1** | If full-file is the primary contract, the recovery path is the default path |
| 3 | Plan key-file guard (output must touch required files; missing-file tracking) | `PlanKeyFileGuardStep`, `implementationValidation.ts` | **Adapt** | The directed-task contract's TARGET section supplies required files; guard verifies context inclusion before the call and output coverage after |
| 4 | Targeted context selection (plan/snippet-driven, not scan-ordered) | `implementationSnippets.ts` (`resolveImplementationSnippetFiles`) | **Port** | TARGET files + files named in CHANGE (imports, imitation targets) load first at full fidelity; inventory and remaining budget after |
| 5 | Baseline typecheck capture + validation diagnostics (compact error feedback into retries) | `implementationDiagnostics.ts` (`captureBaselineTypecheck`, `compactValidationErrors`, `formatValidationSummary`) | **Port** | Repair rounds must see *what failed*, compactly — not just "validation failed" |
| 6 | Retry directives (e.g. missing-export/TS2459 guidance) + deterministic TS6133 unused-import stripper | implementation loop helpers | **Port as pluggable post-processors/diagnostics** | Deterministic fixes cost zero tokens; directives measurably ended retry loops in the benchmark cycle |
| 7 | Info-request loop with budget + forced produce-now | implementation loop | **Defer** | The directed contract front-loads context; revisit only if artifact evidence shows missing-information failures |
| 8 | Stepwise multi-stage plan execution | `implementationStages.ts` | **Defer** | Directed tasks are single-step by contract; multi-step work is decomposed at queue time |
| 9 | Context persona / repo analysis pass | `personas.ts` context | **Drop for directed tasks** | CONTEXT section is authored by the task writer; a model-derived repo summary is redundant here |
| 10 | Persona/message orchestration engine | `workflows/`, being retired per conductor migration | **Not ported** | The engine is the delivery vehicle, not the lesson; extraction (not delegation) avoids re-entangling the retirement path |

## Target architecture

`LocalExecutionBackend` keeps its `ExecutionBackend` interface and is
reduced to a thin adapter over an extracted implementation core:

```text
AttemptRunner
  └─ LocalExecutionBackend (interface unchanged)
       ├─ ContextAssembler      — TARGET/CHANGE files first (full fidelity, fail
       │                          the attempt early if a named target is missing
       │                          or over budget), then inventory + remainder
       ├─ PromptBuilder         — lineage: legacy lead-engineer contract;
       │                          full-file rewrite blocks, Changed Files list
       ├─ FullFileBlockParser   — extracted from the legacy parser, not rewritten
       ├─ applyEditOps          — already shared with the legacy path
       ├─ RepairLoop            — bounded; feeds compact validation diagnostics
       │                          (#5) + retry directives (#6) into round N+1
       └─ ArtifactRecorder      — prompt, raw responses, diagnostics → dashboard
                                  artifacts (attempt_id), success or failure
```

Modules extracted from the legacy harness move to a shared location
consumed by both the (retiring) workflow engine and the execution slice, so
there is exactly one implementation of each lesson during the transition.

## Test plan

1. **Context guarantee** — for a task whose TARGET names files, the built
   prompt contains their full contents, or the attempt fails pre-model with
   a distinct category. Regression test uses a project-dashboard-shaped
   fixture tree.
2. **Replay corpus** — recorded prompts/settings from failed attempts
   (18/20/23/25/27/28) reconstructed as fixtures; the remediated pipeline
   must produce applying edits where the recorded transcript shows the
   model's *content* was right and only the format failed.
3. **Parity** — port the legacy harness's existing tests for each extracted
   module rather than writing new ones where they exist.
4. **Gate** — full conductor suite stays green; no changes to runner/SCM
   invariant tests.

## Acceptance

1. All inventory rows marked Port/Adapt implemented with tests.
2. A fresh re-queue of the task-159 work (new task, fresh budget) completes
   locally: PR with `ui.ts` + `server.ts` registration + passing `npm test`.
3. Attempt artifacts visible in the dashboard for that run.
4. Then tasks 160–162 unblock one merge at a time per the queue runbook.

## Decision points for review

- **D1 — Full-file always, or size-thresholded?** Recommend: full-file
  always for the local backend (files >16 KB are refused targets for local
  tasks rather than falling back to diffs — the fallback would reintroduce
  the failure class).
- **D2 — Extraction vs import.** Recommend: move shared modules to
  `src/implementation/` (new home) and re-point the legacy engine's imports,
  keeping one source of truth; copying would fork the lessons again.
- **D3 — Artifact retention.** Recommend: store prompt + responses for all
  attempts (not just failures) while the local pipeline is re-earning
  trust; revisit volume later.
- **D4 — Task 159.** Recommend: leave it `blocked` as evidence; queue the
  remediation validation as a fresh task when the port lands.
