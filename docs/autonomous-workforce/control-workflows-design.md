# Autonomous Workforce Control Workflows Design

Status: draft for external review
Date: 2026-08-11

This document defines the non-code workflow layer needed to make the
autonomous workforce operationally useful without routing every activity
through the coding backend. It is intentionally public-safe: no private
topology, credentials, hostnames, LAN addresses, service endpoints, or secret
material.

## Problem

The current execution system is strongest when a task is already shaped as a
directed implementation contract. That should remain true. The mistake in the
recent dogfood loop was treating control-surface and coordination work as more
implementation work, including autonomous edits to the dashboard itself.

The missing layer is a set of **control workflows** that observe, analyze,
plan, and prioritize work without directly modifying repositories. Some of
these workflows are fully deterministic. Some need a local LLM, but with a
different objective, prompt, evidence packet, output schema, and gate than the
code-generation path.

## Design Correction

There are two distinct workflow families:

| Family | Purpose | May edit repos? | Example |
| --- | --- | --- | --- |
| Implementation workflow | Produce code changes from a directed task contract | Yes, only through `AttemptRunner` and Forgejo branch/PR flow | Modify one target file and validate |
| Control workflows | Observe, summarize, plan, prioritize, and recommend | No | Summarize why attempt 74 failed |

Control workflows must not call `LocalExecutionBackend`, must not prepare
implementation worktrees, must not commit or push, and must not create PRs.
Their outputs are durable artifacts, recommended actions, queued task drafts,
or operator-facing status. Any transition from a control workflow into
implementation dispatch must pass a deterministic gate and, when configured, a
human/external-agent review gate.

Control-surface repositories such as the dashboard and conductor should default
to review-required planning. Autonomous implementation against those repos is a
higher-risk mode and should require an explicit operator decision per batch,
not merely an enabled background queue.

## System Ownership

Preserve the existing system decomposition:

| System | Responsibility |
| --- | --- |
| `project-dashboard` | Durable system of record for projects, tasks, attempts, workflow outputs, artifacts, review state, priorities, and operator-facing read models |
| `task-flow-conductor` | Scheduler and policy engine for both implementation workflows and control workflows |
| `agent-service` | Optional reuse point for local model routing, notifications, approvals, and future shared model-pool concerns |
| Forgejo | Preferred SCM execution target for implementation workflows only |
| Shared Postgres | Durable state for task/run/control-workflow lifecycle and artifacts |

Do not create a new project registry, work manager, or separate orchestration
service. Add control workflow primitives to the existing conductor/dashboard
boundary.

## Read Boundary

Control workflows may need repository context, but read access must not become
an accidental write path.

For the first Planning / Design iteration, control workflows should use only:

- dashboard-supplied project, repository, task, attempt, and artifact metadata
- dashboard-supplied file inventories when already available
- operator-supplied reference documents
- explicitly attached markdown/design notes

They should not clone repositories at all in the first slice.

If later planning workflows need repository reads, add a dedicated read-only
checkout mechanism with these constraints:

- never use `WorktreeManager`
- never use `TrustedGit`
- never hold the Forgejo write token
- authenticate only with a read-scoped token or anonymous read when available
- mount or materialize the checkout read-only for the model process
- prohibit branch creation, commits, pushes, remotes mutation, hooks execution,
  and submodule writes
- publish only file inventory and approved excerpts into evidence artifacts

This boundary should be structural, not conventional. Reusing the
implementation worktree path for control workflows is a stop condition.

## Workflow Taxonomy

### 1. Status Observation

Purpose: determine whether the portfolio and active runs are healthy.

Execution type: deterministic only.

Inputs:

- active execution attempts
- leases and heartbeats
- attempt start/update timestamps
- configured SLA thresholds
- breaker state
- queue depth
- repository execution policy
- backend availability state when available

Outputs:

- status observations
- warnings
- alerts
- suggested operator controls
- optional automatic fail-closed actions when policy allows

Examples:

- "Attempt has no heartbeat past lease threshold."
- "Attempt has prompt artifact but no model output after expected local-model
  SLA."
- "Repository breaker is open after repeated local failures."
- "Queue is idle even though background-safe work exists."

No LLM is needed. The output should be deterministic, auditable, and suitable
for automation.

### 2. Failure Analysis

Purpose: summarize a failed or degraded run in plain language from standard
evidence.

Execution type: deterministic evidence collection plus optional local LLM
summarization.

Inputs:

- task metadata and directed task contract
- attempt metadata and lifecycle timestamps
- backend/model/policy selection reason
- artifact index and selected artifact contents
- validation output
- parser/apply summaries
- SCM branch/PR/merge metadata
- prior attempts for the same task
- status observations for the attempt

Outputs:

- `run_summary` artifact
- structured failure classification
- timeline
- probable root cause
- supporting evidence references
- recommended next action
- retry/escalation suitability
- confidence

This is the workflow the current dashboard is missing. A useful summary for a
failed run should answer:

- What failed?
- At what stage?
- What evidence supports that?
- Was the model actually called?
- Did the model return output?
- Did parsing/apply/validation/SCM fail?
- Is retry safe?
- Should the next action be narrower tasking, local retry, premium escalation,
  infrastructure repair, or human review?

### 3. Planning / Design

Purpose: turn broad goals into implementation-sized task packets that fit the
local coding flow.

Execution type: LLM-assisted planning with deterministic validation gates.

Inputs:

- high-level goal
- project/repository metadata
- relevant backlog items
- current architecture notes
- dashboard-supplied codebase file map or supplied reference docs
- local capability profile
- directed task contract
- `/plans/evaluate` results
- risk/policy constraints

Outputs:

- markdown plan
- ordered task packet candidates
- dependency chain
- target/reference file list for each task
- acceptance criteria
- local/premium/human suitability
- open questions

Planning output must not dispatch implementation work by default. It should
produce a reviewable plan that can be iterated on by the operator or an
external reviewer. Only accepted task packets move into `tasks:bulk` or
`workq add`.

### 4. Backlog Prioritization

Purpose: suggest which work should move next based on goals, risk, and
available attention.

Execution type: deterministic scoring first; optional LLM explanation.

Inputs:

- user-defined goal priorities and weights
- project priority
- backlog tasks and labels
- repository write policy
- estimated risk
- local capability fit
- recent failure history
- review burden
- time sensitivity
- background suitability
- portfolio-mode attention policy

Outputs:

- ranked backlog suggestions
- score breakdown
- background-safe queue candidates
- attention-required candidates
- deprioritized/risky items with reasons
- optional human-readable narrative

The deterministic score is authoritative. The LLM may explain the ranking and
spot qualitative tradeoffs, but must not silently override the rubric.

## Common Control Workflow Model

Add a provider-neutral workflow lifecycle distinct from implementation
attempts.

```text
ControlWorkflowRun
  id
  workflow_type
  project_id
  task_id nullable
  attempt_id nullable
  status
  requested_by
  policy
  inputs_hash
  idempotency_key
  started_at
  completed_at
  result_summary
  result_artifact_id
  failure_category nullable
```

Suggested statuses:

```text
queued
running
succeeded
failed
blocked
cancelled
```

Suggested workflow types:

```text
status_observation
failure_analysis
planning_design
backlog_prioritization
```

Control workflow runs may reference task execution attempts, but they are not
execution attempts. A failed summary job must not count as a failed coding
attempt.

`inputs_hash` must be computed from canonical JSON: sorted object keys,
normalized timestamps/strings, and no nondeterministic field ordering. The same
inputs must produce the same hash across processes.

Control workflow recovery is intentionally simple. On conductor startup, any
`running` control workflow run owned by a dead process is marked `failed` with
failure category `orphaned_control_run`. Because control workflow work is
idempotent by `inputs_hash` and `idempotency_key`, the operator or scheduler
may start a replacement run. Do not leave control runs stranded in `running`.

## Artifact Contracts

Control workflows should write structured artifacts through `project-dashboard`
using attempt/task/project references as applicable.

### Evidence Packet

Artifact kind: `run_evidence_packet`

Produced deterministically before any LLM summarization.

Schema:

```json
{
  "task": {
    "id": 0,
    "title": "",
    "status": "",
    "repository_id": 0,
    "target_entries": [],
    "reference_files": []
  },
  "attempt": {
    "id": 0,
    "attempt_number": 0,
    "status": "",
    "backend": "",
    "model": "",
    "selection_reason": "",
    "created_at": "",
    "started_at": "",
    "completed_at": "",
    "failure_category": "",
    "validation_status": "",
    "merge_status": ""
  },
  "timeline": [],
  "artifact_index": [],
  "validation": {
    "command": "",
    "status": "",
    "summary": ""
  },
  "scm": {
    "branch": "",
    "pr_url": "",
    "merge_status": ""
  },
  "observations": []
}
```

The evidence packet should be compact and redacted. It should include artifact
metadata by default and only include artifact contents that are safe and useful
for summarization.

Redaction must be mechanical and deny-by-default:

- include artifact metadata for all attempt artifacts
- include content excerpts only from an allowlist of artifact kinds, initially:
  `local_parse_result`, `local_validation_diagnostics`,
  `local_accumulated_rewrites`, validation output, and SCM/merge result text
- exclude raw prompts and raw model outputs by default; allow only bounded
  excerpts after explicit policy approval
- run every excerpt through the existing secret scanner before persistence or
  model use
- run the placeholder-residue check before persistence or model use
- cap each excerpt by byte count and line count
- record omitted artifact kinds and omission reasons in the evidence packet

If an artifact cannot pass these rules, the evidence packet should reference
its metadata only.

### Run Summary

Artifact kind: `run_summary`

Schema:

```json
{
  "summary": "",
  "stage": "",
  "root_cause": "",
  "timeline": [
    {
      "time": "",
      "event": "",
      "evidence": ""
    }
  ],
  "evidence": [
    {
      "kind": "",
      "artifact_id": 0,
      "note": ""
    }
  ],
  "recommended_next_action": "",
  "retry_safety": "safe | unsafe | conditional | unknown",
  "routing_recommendation": "retry_local | split_task | premium | human | infrastructure",
  "confidence": "low | medium | high"
}
```

`stage` is a fixed enum:

```text
context
model
parse
apply
validation
scm
merge
policy
unknown
```

Schema validation must require at least one evidence reference. A run summary
without evidence citations is invalid, even if the prose is plausible.

The dashboard should display this artifact in the selected run panel. If a run
has no summary artifact, it should show a deterministic fallback and offer a
`Generate summary` action if the local summarizer is available.

### Planning Output

Artifact kind: `planning_design_output`

Schema:

```json
{
  "goal": "",
  "summary": "",
  "tasks": [
    {
      "title": "",
      "description": "",
      "target_entries": [],
      "reference_files": [],
      "acceptance": "",
      "depends_on": [],
      "routing": "local | premium | human",
      "risk": "",
      "reason": ""
    }
  ],
  "open_questions": [],
  "review_status": "draft | approved | rejected | revised"
}
```

### Backlog Prioritization Output

Artifact kind: `backlog_prioritization`

Schema:

```json
{
  "goal_weights": {},
  "ranked_items": [
    {
      "task_id": 0,
      "score": 0,
      "score_breakdown": {},
      "recommended_lane": "attention | background | blocked | defer",
      "reason": ""
    }
  ],
  "summary": ""
}
```

## Execution Boundary

Introduce a control-workflow runner contract separate from implementation
backends.

```text
ControlWorkflowRunner
  collectInputs()
  runDeterministicStage()
  maybeCallModel()
  validateOutput()
  persistArtifacts()
  updateReadModels()
```

The runner may call a local LLM through a summarizer/planner interface, but it
must not receive a writable worktree or SCM credential.

Control-workflow model calls must yield to implementation attempts. The first
policy should be: if an implementation attempt is in flight on the local model
slot, defer summarization/planning/prioritization model calls until the slot is
idle. Deterministic status observation and evidence collection may still run.

Suggested LLM interfaces:

```text
LocalSummarizationBackend
LocalPlanningBackend
LocalPrioritizationBackend
```

These are not execution backends. They do not apply patches. They return
structured text/JSON artifacts that are validated before persistence.

## Gates

### Universal Control Workflow Gates

- no repository writes
- no implementation worktree or `WorktreeManager` reuse
- no SCM credentials in the model process
- no secret-bearing artifact contents sent to the model
- artifact-kind allowlist before content inclusion
- secret-scan and placeholder-residue checks before model calls
- schema validation after model calls
- persisted input hash for auditability
- idempotency key per workflow run

### Failure Analysis Gates

- if evidence packet cannot be built, fail before model call
- if no model output is returned, persist deterministic failure summary
- if model output fails schema validation, persist raw failure category but do
  not block the original task
- never change the original attempt status based solely on LLM summary

### Planning / Design Gates

- generated tasks are drafts until reviewed
- every proposed implementation task must satisfy the directed task contract
- every proposed task must pass `/plans/evaluate`
- broad/multi-file plans remain design artifacts, not dispatchable tasks
- task creation requires explicit approval policy

### Backlog Prioritization Gates

- deterministic score breakdown must be present
- LLM narrative cannot change score values
- background recommendations must satisfy repository policy and risk threshold
- attention-required work must not be queued in background portfolio modes

## Dashboard Implications

Replace the current count-repetition summary with run-centered controls.

Selected run panel should show, in priority order:

1. current run summary artifact, if present
2. deterministic fallback summary if no artifact exists
3. evidence packet links/metadata
4. stage/timeline
5. failure/root cause
6. recommended next action
7. controls allowed by policy:
   - generate summary
   - retry
   - abort
   - mark human-required
   - create planning follow-up

Portfolio counts remain useful as navigation cards, but they should not be
repeated as an "operator summary." Operator-facing summary should answer:

- What needs attention now?
- Which runs are stuck or outside SLA?
- Which failed runs have no analysis yet?
- Which plans are ready for review?
- Which background-safe tasks are available?

## Status Observation Details

Define SLA rules per workflow/backend:

```text
local_model_prompt_to_output_ms
validation_max_ms
scm_push_max_ms
pr_create_max_ms
heartbeat_grace_ms
lease_expiry_grace_ms
```

Observation examples:

| Observation | Severity | Suggested action |
| --- | --- | --- |
| Prompt artifact exists but no model output past SLA | warning | continue, abort, or retry depending on policy |
| Attempt lease expired | critical | recovery sweep |
| Validation running past SLA | warning | inspect validation process |
| Repeated local model timeout for same target file | warning | split task or route planning |
| Breaker opened | critical | pause affected repo |

Abort/retry controls should be deterministic and policy-bound. A user action
can abort an active control workflow or implementation attempt; automatic abort
requires explicit policy and evidence that the attempt is unrecoverable.

## Failure Analysis Prompt Shape

The summarizer prompt should be stable and narrow:

```text
You summarize an execution attempt. You do not propose code changes unless the
evidence directly supports them. Use only the evidence packet. If evidence is
missing, say so. Return JSON matching the run_summary schema.
```

The prompt should include:

- evidence packet JSON
- artifact content excerpts only when safe and relevant
- failure taxonomy
- allowed routing recommendations
- output schema

The summarizer should not see raw secrets, full environment files, private
tokens, or unrelated repository content.

## Planning / Design Prompt Shape

The planner prompt should produce task packets, not code:

```text
Turn the goal into implementation-sized task packets for the directed local
coding flow. Do not write code. Prefer single-file tasks. State dependencies.
Each task must include CONTEXT, TARGET, CHANGE, and ACCEPTANCE.
```

Planner output should be run through:

1. schema validation
2. directed task contract parser
3. `/plans/evaluate`
4. human/external-agent review
5. optional `tasks:bulk` creation

## Backlog Prioritization Rubric

Use deterministic weighted scoring:

```text
score =
  goal_alignment * weight_goal_alignment
  + project_priority * weight_project_priority
  + urgency * weight_urgency
  + local_fit * weight_local_fit
  + background_safety * weight_background_safety
  - risk * weight_risk
  - review_burden * weight_review_burden
  - recent_failure_penalty * weight_recent_failure
```

Weights should be user-configurable per portfolio mode. Example modes:

- "overnight background improvement"
- "operator review window"
- "revenue-focused"
- "homeops stability"
- "creative buildout"

The prioritizer should output both ranked suggestions and "do not run now"
items with reasons.

Start with labeled priorities on both projects and tasks:

```text
urgent
high
normal
low
```

Project priority should dominate task priority. For example, a low-priority
task in a high-priority project should usually rank above a high-priority task
in a low-priority project. The exact weights are configurable, but the default
ordering should reflect portfolio goals first and task urgency second.

Background or overnight suggestions should be risk-sensitive. Low-risk work in
high-priority projects should be pulled forward; high-risk work should be held
for an operator review window even if it has strong goal alignment.

The dashboard should eventually provide an interactive priority-weighting
surface, such as click/drag card sorting for projects, goals, and backlog
lanes. That interface should update the deterministic scoring weights rather
than directly queueing implementation work.

## Implementation Phases

### C1 - Control Workflow Design and Schema

- Add dedicated durable `control_workflow_runs` model.
- Add artifact kinds for evidence packets, run summaries, planning outputs,
  and backlog prioritization.
- Add read endpoints for selected run summaries.
- Add canonical `inputs_hash`, idempotency keys, and startup orphan sweep.
- No LLM calls yet.

### C2 - Status Observation

- Implement deterministic observation engine.
- Add SLA configuration.
- Show stuck/warning states in portfolio UI.
- Add manual abort/retry controls behind policy.

### C3 - Failure Evidence Bundles

- Build deterministic evidence packet generator for a task attempt.
- Persist `run_evidence_packet`.
- Show evidence metadata in selected run panel.
- Generate deterministic fallback summaries with no LLM.

### C4 - Local Run Summarizer

- Add local summarization backend.
- Generate and persist `run_summary` artifacts.
- Validate model output schema.
- Add "Generate summary" action.
- Add automatic summaries only for `blocked` and `human_required` outcomes.
- Defer model calls while implementation attempts are using the local model
  slot.

### C5 - Planning / Design Workflow

- Add reviewed planning run type.
- Produce task packet drafts.
- Run parser and `/plans/evaluate` against every task candidate.
- Store markdown/API review output.
- Require review before task creation.
- Use dashboard metadata and operator-supplied references only; no repository
  checkout in the first planning slice.

### C6 - Backlog Prioritization

- Add goal weights and scoring rubric.
- Produce ranked suggestions.
- Add background-safe/attention-required lanes.
- Optional LLM narrative after deterministic scoring.

## Proposed Review Resolutions

These are the recommended positions for the first implementation pass.

1. Use a dedicated `control_workflow_runs` table, with outputs in the existing
   artifact model. Do not reuse the execution attempts table. Attempt rows carry
   implementation semantics that should not apply to summaries or planning
   jobs.
2. Take no automatic actions from LLM failure analysis initially.
   Deterministic status observation may take fail-closed actions when policy
   allows, but a model-generated summary should only recommend. A future
   exception can be earned with data for cases where `retry_safety = safe` and
   the deterministic failure class independently agrees.
3. Generate failure summaries on demand first, plus automatic summaries for
   `blocked` and `human_required` outcomes. These are the outcomes that cost
   operator attention. Do not auto-summarize every failed attempt until
   usefulness and model contention are measured.
4. Keep planning outputs as markdown/artifacts until explicit approval. Provide
   a cheap "accept packet" action that runs the directed task parser and
   `/plans/evaluate` at acceptance time, then creates tasks. Do not create draft
   queue tasks that can be accidentally claimed.
5. Start backlog prioritization with labeled project/task priorities:
   `urgent`, `high`, `normal`, and `low`. Project priority dominates task
   priority; risk gates background/overnight suggestions.
6. Defer `agent-service` integration. The conductor's existing local model
   client is the shortest proven path for summarization. Add `agent-service`
   only when a second consumer or model-routing requirement justifies the
   dependency.

## Recommended First Slice

Start with C2 and C3, not more dashboard UI work:

```text
status observations
-> deterministic run evidence packet
-> selected-run deterministic fallback summary
-> local LLM run_summary generation
```

This gives the operator useful failure context and produces evidence that can
feed future local repair attempts without increasing the risk of autonomous
self-editing.
