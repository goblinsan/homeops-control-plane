# Control Workflows Implementation Plan

Status: draft for review
Date: 2026-08-11
Design source: `docs/autonomous-workforce/control-workflows-design.md`

This plan sequences implementation of non-code control workflows for the
autonomous workforce. The goal is to add operational autonomy without routing
status observation, failure analysis, planning, or backlog prioritization
through the code-generation workflow.

This document is public-safe and intentionally avoids private topology,
credentials, endpoints, hostnames, LAN addresses, and secret material.

## Operating Invariants

These invariants apply to every package below:

- Control workflows do not edit repositories.
- Control workflows do not prepare implementation worktrees.
- Control workflows do not call `LocalExecutionBackend`.
- Control workflows do not use `WorktreeManager` or `TrustedGit`.
- Control workflows do not hold SCM write credentials.
- Control workflow failures do not count as implementation attempt failures.
- LLM-generated summaries or plans do not automatically mutate task status,
  create implementation tasks, retry runs, escalate runs, commit, push, or open
  PRs.
- Model calls for control workflows defer while implementation attempts are
  using the local model slot.
- Generated content must pass schema validation and redaction gates before
  being persisted or shown as trusted output.

## Sequencing Overview

```text
P0 - Freeze unsafe dogfood posture
-> P1 - Control workflow schema and APIs
-> P2 - Deterministic status observation
-> P3 - Deterministic run evidence packets
-> P4 - Selected-run read model and dashboard fallback summary
-> P5 - Local run summarizer
-> P6 - Planning/design artifact workflow
-> P7 - Backlog prioritization scoring
-> P8 - Review, hardening, and rollout policy
```

Recommended first implementation slice:

```text
P0 -> P1 -> P2 -> P3 -> P4
```

That slice produces useful operator-facing run context without adding any LLM
dependency or repository-read capability.

## P0 - Freeze Unsafe Dogfood Posture

Priority: P0
Repos: `project-dashboard`, `task-flow-conductor`, `homeops-control-plane`
LLM: none

### Objective

Prevent control-surface work from being claimed by the implementation
dispatcher unless the operator explicitly opts in per batch.

### Work

- Document that `project-dashboard` and `task-flow-conductor` default to
  review-required planning for autonomous work.
- Add repository-level `dispatch_mode`:
  - `background_ok`
  - `manual_batch`
- Enforce `dispatch_mode` in the `project-dashboard` claim path, not only in
  conductor policy:
  - repositories with `dispatch_mode = background_ok` remain eligible for
    normal background claims when their other policy gates pass
  - repositories with `dispatch_mode = manual_batch` are invisible to normal
    claim requests
  - a `manual_batch` repository can be claimed only when the claim request
    carries explicit batch authorization for that repository/batch
- Default control-surface repositories to `manual_batch`.
- Add migration/backfill:
  - existing write-enabled ordinary repositories default to `background_ok`
  - `project-dashboard` and `task-flow-conductor` default to `manual_batch`
- Confirm dispatch remains paused before and after this plan's implementation
  tasks unless explicitly resumed.
- Add a runbook note explaining when self-editing batches are allowed.

### Acceptance

- A control-surface repo cannot be claimed by implementation dispatch merely
  because the global dispatch switch is enabled.
- The dashboard claim query excludes `manual_batch` repositories unless
  explicit batch authorization is present.
- There is a documented explicit operator action required before a
  control-surface implementation batch can run.
- Tests cover both normal background claims and manual-batch authorized claims.

### Stop Conditions

- Any implementation task targeting a control-surface repo becomes claimable
  without explicit operator approval.
- `dispatch_mode` is enforced only in conductor code and not in the dashboard
  claim transaction.
- Any package attempts to use autonomous implementation dispatch to modify the
  control workflow implementation itself.

## P1 - Control Workflow Schema and APIs

Priority: P0
Primary repo: `project-dashboard`
Secondary repo: `task-flow-conductor`
LLM: none

### Objective

Create durable lifecycle state for non-code control workflow runs while keeping
outputs in the existing artifact model.

### Work

- Add a dedicated `control_workflow_runs` table.
- Add schema/version migration tests, including live-database idempotency.
- Add API endpoints to:
  - create a control workflow run
  - list control workflow runs by project/task/attempt/type/status
  - fetch one control workflow run
  - patch status/result metadata
- Add dashboard-side artifact-kind validation for:
  - `run_evidence_packet`
  - `run_summary`
  - `planning_design_output`
  - `backlog_prioritization`
- Keep content-schema validation conductor-side before persistence:
  - `run_summary.stage` enum
  - required summary evidence reference
  - allowed retry/routing recommendation enums
  - planning task-packet schema
  - backlog prioritization score schema
- Add canonical `inputs_hash` generation rules.
- Add idempotency-key handling.
- Add startup recovery behavior in the conductor:
  - mark orphaned `running` control runs as `failed`
  - use failure category `orphaned_control_run`
  - allow rerun with the same canonical inputs.

### Suggested Table Shape

```text
control_workflow_runs
  id
  workflow_type
  project_id nullable
  task_id nullable
  attempt_id nullable
  status
  requested_by
  policy json/text
  inputs_hash
  idempotency_key
  started_at
  completed_at
  result_summary
  result_artifact_id nullable
  failure_category nullable
  created_at
  updated_at
```

### Acceptance

- Control workflow runs are stored separately from implementation attempts.
- A failed control workflow run does not affect task execution attempt metrics,
  breakers, budgets, or retry counts.
- `inputs_hash` is stable across key ordering differences.
- Duplicate idempotency keys do not create duplicate running work.
- Startup recovery marks stranded `running` control runs failed and rerunnable.
- Dashboard rejects unknown control artifact kind strings.
- Conductor validates content schemas before writing control artifacts.
- Tests cover schema migration, API CRUD/list paths, canonical hash behavior,
  artifact-kind validation, content-schema validation, and orphan recovery.

### Stop Conditions

- Control workflow lifecycle is added to the implementation attempts table.
- Control workflow status changes affect implementation attempt failure counts.
- Any control workflow API gains repository write or SCM capability.
- Dashboard accepts arbitrary control artifact kind strings.
- Control artifact content is persisted before conductor-side schema
  validation.

## P2 - Deterministic Status Observation

Priority: P0
Primary repo: `task-flow-conductor`
Secondary repo: `project-dashboard`
LLM: none

### Objective

Produce deterministic health observations for active runs and portfolio state.

### Work

- Add status observation runner.
- Define SLA config keys:
  - `local_model_prompt_to_output_ms`
  - `validation_max_ms`
  - `scm_push_max_ms`
  - `pr_create_max_ms`
  - `heartbeat_grace_ms`
  - `lease_expiry_grace_ms`
- Derive observations from:
  - attempt status
  - heartbeat and lease timestamps
  - artifact presence/absence
  - validation status
  - repository breaker state
  - queue depth
- Store observations in a current-state read model keyed by deterministic
  finding identity, such as attempt id, observation type, and evidence hash.
- Persist observation history only on state transitions:
  - new finding appears
  - severity changes
  - finding clears
- Do not create a new `control_workflow_runs` row or artifact on every sweep
  tick. A control workflow run represents an on-demand or scheduled analysis
  pass, not a heartbeat.
- Add deterministic severity levels:
  - `info`
  - `warning`
  - `critical`
- Add read endpoint or portfolio read-model field for active observations.

### Observation Examples

| Observation | Severity | Deterministic trigger |
| --- | --- | --- |
| no model output | warning | prompt artifact exists, no model output past SLA |
| lease expired | critical | active attempt lease expired |
| validation slow | warning | validation phase exceeds SLA |
| breaker open | critical | repository or global breaker open |
| idle with background-safe work | info | queue empty/runnable candidate exists |

### Acceptance

- No LLM calls are made.
- Observations are deterministic from dashboard/conductor state.
- Observation output includes evidence fields for each finding.
- Repeated sweeps with unchanged findings do not create duplicate persisted
  observations.
- Finding appearance, severity change, and clear transitions are persisted.
- A run with prompt artifact and no model output past SLA is flagged.
- A lease-expired attempt is flagged critical.
- Tests cover at least prompt-without-output, lease expiry, breaker open, and
  no-warning healthy state.
- Tests cover deduplication and clear-transition behavior.

### Stop Conditions

- Status observation attempts to summarize with an LLM.
- Status observation modifies task status except through an explicit
  deterministic policy already approved for fail-closed behavior.
- Observation sweeps persist duplicate rows/artifacts for unchanged findings.

## P3 - Deterministic Run Evidence Packets

Priority: P0
Primary repo: `task-flow-conductor`
Secondary repo: `project-dashboard`
LLM: none

### Objective

Build a standard evidence packet for one implementation attempt. This packet is
the input to deterministic fallback summaries and future local LLM summaries.

### Work

- Implement `run_evidence_packet` builder.
- Gather:
  - task metadata
  - attempt metadata
  - selected repository id
  - target entries and reference files
  - artifact index
  - lifecycle timestamps
  - backend/model/selection reason
  - validation status/output summary
  - SCM branch/PR/merge metadata
  - status observations
  - prior attempts for the same task
- Include artifact metadata for all artifacts.
- Include content excerpts only from the allowlist:
  - `local_parse_result`
  - `local_validation_diagnostics`
  - `local_accumulated_rewrites`
  - validation output
  - SCM/merge result text
- Exclude raw prompts and raw model outputs by default.
- Run every excerpt through:
  - existing secret scanner
  - placeholder-residue check
  - byte cap
  - line cap
- Record omitted artifact kinds and omission reasons.
- Persist the packet as an attempt-linked artifact.

### Acceptance

- Evidence packets can be generated for succeeded, failed, blocked, and
  running attempts.
- Raw prompt/model output contents are omitted by default.
- Secret scanner rejection prevents excerpt inclusion and records the omission.
- Packet includes enough metadata to answer whether the model was called and
  whether it returned output.
- Tests cover allowlisted excerpts, denied artifact kinds, excerpt caps,
  omission reasons, and artifact persistence.

### Stop Conditions

- Raw prompt/model output is included by default.
- Evidence packet builder reads repository files through an implementation
  worktree.
- Secret-bearing content can be persisted in an evidence packet.

## P4 - Selected-Run Read Model and Deterministic Fallback Summary

Priority: P1
Primary repo: `project-dashboard`
Secondary repo: `task-flow-conductor`
LLM: none

### Objective

Make selected run details useful before adding any LLM summarization.

### Work

- Add selected-run read endpoint or extend existing attempt endpoint to include:
  - latest `run_summary` artifact metadata/content when present
  - latest `run_evidence_packet` metadata
  - deterministic fallback summary when no `run_summary` exists
  - status observations
  - allowed controls
- Implement policy-gated selected-run controls:
  - abort active attempt
  - retry/reopen eligible task
  - mark human-required
- Use existing lifecycle mechanics where available:
  - abort patches the attempt to a terminal state and relies on the runner's
    heartbeat/abort signal path
  - retry uses existing reopen semantics rather than creating a new task
  - mark-human-required patches task/attempt disposition through existing
    dashboard APIs
- Build deterministic fallback summary from evidence:
  - stage
  - failure category
  - artifact presence
  - validation status
  - merge status
  - recommended deterministic next step when obvious
- Replace useless operator count repetition with run-centered information in
  the UI.
- Keep portfolio counts only as navigation/status cards.

### Acceptance

- Selecting a failed attempt shows what stage failed using deterministic data.
- Selecting an attempt with prompt artifact but no model output says that
  plainly.
- Selecting a validation failure shows validation status and evidence link.
- Allowed controls are shown only when policy permits them.
- Abort, retry/reopen, and mark-human-required each have deterministic API
  tests.
- Abort of an active attempt is observed by the runner without creating
  duplicate side effects.
- No historical failure wall appears in place of selected-run details.
- Tests cover selected run with:
  - no summary artifact
  - evidence packet present
  - model-output missing
  - validation failure
  - succeeded run

### Stop Conditions

- The UI reintroduces a count-only "operator summary" as the primary detail.
- The UI requires an LLM summary before showing useful run information.
- Selected-run controls bypass policy gates.
- Retry creates duplicate task identity instead of preserving/reopening the
  existing task.

## P5 - Local Run Summarizer

Priority: P1
Primary repo: `task-flow-conductor`
Secondary repo: `project-dashboard`
LLM: local summarization only

### Objective

Generate structured `run_summary` artifacts from evidence packets using a
local LLM, without any repository write capability.

### Work

- Add `LocalSummarizationBackend`.
- Use existing conductor local model client initially.
- Defer `agent-service` integration.
- Enforce model-yield policy:
  - if implementation attempt is using the local model slot, defer summary
    model call
  - deterministic evidence/status work may still run
- Use stable summarizer prompt:
  - summarize one attempt
  - use only evidence packet
  - cite evidence
  - return JSON matching schema
- Validate output schema:
  - `stage` enum
  - at least one evidence reference
  - allowed retry/routing enums
  - confidence enum
- Persist `run_summary` artifact.
- Add manual `Generate summary` action.
- Add automatic summaries only for:
  - `blocked`
  - `human_required`
- Do not automatically act on summary recommendations.

### Acceptance

- Summary generation does not receive a writable worktree or SCM credential.
- Summary generation is skipped/deferred while local implementation model work
  is in flight.
- Invalid JSON/schema output fails the control workflow without changing the
  original attempt.
- Summary artifact cites at least one evidence reference.
- Automatic generation runs only for `blocked` and `human_required` outcomes.
- Tests cover valid summary, schema failure, missing evidence citation,
  model-output timeout, and model-yield behavior.

### Stop Conditions

- LLM summary changes task/attempt status automatically.
- LLM summary triggers retry/escalation automatically.
- Summarizer sees raw prompt/model output by default.
- Summarizer uses implementation backend or worktree path.

## P6 - Planning / Design Artifact Workflow

Priority: P2
Primary repo: `task-flow-conductor`
Secondary repo: `project-dashboard`
LLM: local planning only

### Objective

Turn broad goals into reviewable implementation task packets without creating
claimable tasks until explicit acceptance.

### Work

- Add `planning_design` control workflow type.
- Inputs for first slice:
  - operator-supplied goal
  - dashboard metadata
  - operator-supplied reference docs
  - directed task contract
  - capability profile
- No repository checkout in the first planning slice.
- Add `LocalPlanningBackend`.
- Produce `planning_design_output` artifact with task packet candidates.
- Validate every candidate:
  - schema
  - directed task parser
  - target/reference structure
  - `/plans/evaluate`
- Add review status:
  - `draft`
  - `approved`
  - `rejected`
  - `revised`
- Add "accept packet" action:
  - reruns parser and `/plans/evaluate` at acceptance time
  - creates tasks only after acceptance
  - does not create draft tasks in claimable statuses

### Acceptance

- Planning produces artifact output, not implementation changes.
- Planning output can be reviewed as markdown/API data.
- Candidate task packets pass parser and `/plans/evaluate` before acceptance.
- Accepted packets create tasks only through explicit action.
- Draft plans cannot be claimed by implementation dispatch.
- Tests cover invalid task packet rejection, plan artifact persistence,
  accepted packet task creation, and no-checkout behavior.

### Stop Conditions

- Planning workflow clones a repository in the first slice.
- Planning workflow creates claimable tasks before explicit acceptance.
- Planning output bypasses directed task contract validation.

## P7 - Roadmap-Aware Backlog Prioritization

Priority: P2
Primary repo: `project-dashboard`
Secondary repo: `task-flow-conductor`
LLM: optional narrative only

### Objective

Represent real project roadmaps in `project-dashboard`, then rank roadmap
candidates using deterministic goal/project/milestone/item/task/risk scoring.
Only after an operator accepts a roadmap item should it become executable task
packets.

### Work

- Add a durable roadmap layer owned by `project-dashboard`:
  - project
  - milestone
  - roadmap group
  - roadmap step
  - linked executable task(s), when a step has been decomposed
- Roadmap records are planning state, not queue state. They must not be
  claimable by the conductor until explicit acceptance creates or opens tasks.
- Add project priority labels:
  - `urgent`
  - `high`
  - `normal`
  - `low`
- Add milestone and roadmap-item priority labels using the same vocabulary.
- Add roadmap item risk:
  - `low`
  - `medium`
  - `high`
- Map existing task priority/risk fields into the same scoring model for
  already-decomposed work.
- Add portfolio modes:
  - `overnight_background_improvement`
  - `operator_review_window`
  - `revenue_focused`
  - `homeops_stability`
  - `creative_buildout`
- Add configurable scoring weights.
- Implement deterministic score:
  - project priority dominates task priority
  - milestone priority influences ordering within a project
  - roadmap item priority influences ordering within a milestone
  - low-risk high-priority work ranks higher for background mode
  - high-risk work is held for review-window mode
  - recent failure history penalizes candidates
  - review burden penalizes candidates
- Produce `backlog_prioritization` artifact.
- Add optional LLM narrative after scoring.
- Add dashboard visibility for roadmap milestones/groups/steps.
- Add future UI design note for click/drag priority weighting and queueing
  controls, but do not let prioritization mutate the queue automatically.

### Acceptance

- Deterministic score breakdown is present for every ranked item.
- Roadmap items can exist without creating any claimable task.
- Cross-project roadmap links are rejected.
- A low-priority task in a high-priority project ranks above a high-priority
  task in a low-priority project under default weights.
- A low-priority roadmap item in a high-priority project ranks above a
  high-priority roadmap item in a low-priority project under default weights.
- Background mode suppresses high-risk suggestions.
- LLM narrative cannot change score values or ranking.
- Tests cover scoring order, risk gating, failure penalty, and narrative
  immutability.

### Stop Conditions

- LLM chooses or mutates ranking without deterministic score support.
- Prioritizer queues implementation tasks automatically.
- A roadmap item becomes claimable without explicit task creation/opening.
- Attention-required work is recommended for background mode.

## P8 - Review, Hardening, and Rollout Policy

Priority: P1
Repos: all touched repos
LLM: none required

### Objective

Establish the rollout posture for control workflows before enabling automatic
summaries or planner-assisted task creation.

### Work

- Add an operator runbook for control workflows.
- Document when automatic blocked/human-required summaries are enabled.
- Document how to disable all control LLM calls while leaving deterministic
  status observation active.
- Add metrics:
  - evidence packets generated
  - summaries generated
  - summaries failed schema validation
  - summaries viewed
  - accepted planning packets
  - rejected planning packets
  - prioritization suggestions accepted/rejected
  - attempt wall-clock duration by repository/workflow/backend/model
  - queue wait time, claim-to-start time, prompt-to-first-output time, and
    prompt-to-final-output time when artifacts make those timestamps available
  - validation command count, validation duration, validation status, and
    validation failure category by attempt
  - duplicate-validation indicators for attempts where the backend already
    validated a merged rewrite set and the runner then repeated the same
    repository validation before PR creation
- Add dashboard/read-model views for:
  - runs needing summary
  - stuck runs
  - failed summaries
  - plans awaiting review
  - background-safe suggestions
  - slow attempts and slow validation gates
  - backend/runner validation cost trends
- Keep the runner's final validation as the pre-push authority until the
  observed data shows the duplicated validation cost is material. If it is,
  evaluate a `validated`/`validation_evidence` result flag so the runner can
  trust-but-spot-check without weakening the safety boundary.

### Acceptance

- Deterministic observation can run with all LLM control workflows disabled.
- Automatic LLM summaries can be enabled/disabled by policy.
- Control workflow metrics are visible enough to judge usefulness.
- Observation metrics are sufficient to answer whether repeated validation is
  materially increasing attempt wall-time for a repository or workflow profile.
- Planner outputs remain review-required.
- Backlog prioritization remains suggestive.

### Stop Conditions

- Automatic control workflows begin creating or dispatching implementation
  tasks without explicit acceptance.
- Control LLM calls contend with implementation attempts after the yield policy
  is enabled.
- Attempt performance metrics require raw secret-bearing logs, raw prompts, or
  per-tick persistence instead of bounded derived measurements.

## Cross-Package Test Matrix

| Risk | Required test |
| --- | --- |
| Control-surface repo claimable without batch authorization | Claim API test: `manual_batch` repository is invisible to normal claims and claimable only with explicit batch authorization |
| Control workflow becomes implementation attempt | Unit/API test: control run failure does not affect attempt metrics |
| Read path reuses write path | Test/no-import guard against `WorktreeManager` and `TrustedGit` in control workflow modules |
| Secret exposure | Evidence excerpt tests with scanner rejection |
| Orphaned runs | Startup sweep test |
| Model contention | Scheduler test defers control model call while implementation attempt is in flight |
| Hallucinated summary | Schema test requires evidence references |
| Draft task claimability | Planning acceptance test proves drafts are artifacts, not open tasks |
| LLM ranking authority | Prioritization test proves narrative cannot change score |

## Suggested Review Order

1. Review P0-P4 as the first implementation milestone.
2. Implement P0-P4 and pause for evidence.
3. Review P5 with real evidence packets from recent failed/succeeded runs.
4. Implement P5 behind manual generation first.
5. Review P6 and P7 separately; they create new operator workflows and should
   not be bundled with run summarization.

## First Milestone Exit Criteria

The first milestone is complete when:

- control workflow lifecycle state exists
- status observations are deterministic and visible
- evidence packets can be generated for existing attempts
- selected run details show a deterministic fallback summary
- no LLM calls are required
- no repository read/write capability is added to control workflows
- no implementation dispatch behavior changes except explicit safety policy
  around control-surface repos

Only after this milestone should local LLM run summarization be enabled.
