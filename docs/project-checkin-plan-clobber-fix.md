# Project Check-In Plan Clobber Fix

This document is an explicit execution plan for fixing the `agent-service`
regression where scheduled `project_checkin` runs overwrite rich plans with
partial low-fidelity data.

Follow these steps in order. Do not improvise the architecture.

## Bug Statement

Recurring `project_checkin` runs are allowed to call `plan_upsert` with partial
payloads. Those payloads are being persisted as if they are complete canonical
plan replacements.

This destroys rich durable plans by erasing or replacing:

- milestones
- tasks
- tracked metrics
- baseline facts
- success criteria
- cadence
- supporting sections
- other structured metadata

The result is a nearly empty plan in mobile and web planning views.

## Required Fix

Implement the fix in `agent-service` with these exact rules:

1. Scheduled `project_checkin` runs must not be allowed to call the general
   `plan_upsert` tool.
2. Add a dedicated narrow tool for scheduled check-ins to write only lightweight
   plan progress metadata without touching canonical structure.
3. Keep `plan_upsert` available for normal explicit planning flows, imports, and
   user-driven plan editing.
4. Add a second defensive safeguard so that partial plan updates cannot erase
   structured fields even if they reach the persistence layer unexpectedly.

Do not solve this only with prompt wording.

## Exact Implementation Steps

### Step 1: Find the scheduled `project_checkin` execution path

Locate the code in `agent-service` that:

- creates or executes `project_checkin` scheduled jobs
- builds the tool registry for those runs
- determines which tools are available during a scheduled check-in

You must identify the exact place where the tool list for `project_checkin` runs
is assembled.

### Step 2: Remove `plan_upsert` from scheduled `project_checkin` runs

Modify the scheduled `project_checkin` tool set so it cannot call the generic
plan-edit tool.

For `job_type=project_checkin`:

- allow read tools such as plan listing / memory / recent events / notifications
  as needed
- do not register or expose the generic `plan_upsert` tool

This restriction must be enforced in code.

Do not rely on prompt instructions like “avoid plan_upsert unless necessary.”

### Step 3: Add a new narrow tool for safe progress updates

Create a dedicated tool specifically for scheduled check-ins. Name it
something unambiguous, for example:

- `plan_progress_update`

Its behavior must be strictly limited.

It may update only these fields on an existing plan:

- optional short summary
- optional status
- optional tags if explicitly supplied

It may append or replace only a lightweight progress note field if such a field
already exists in the model, or append a user event / progress contribution if
that is the existing pattern.

It must not modify, clear, or replace any of the following:

- `milestones`
- `steps`
- `objectives`
- `principles`
- `tracked_metrics`
- `baseline_facts`
- `success_criteria`
- `cadence`
- `supporting_sections`
- `metrics`
- `data_sources`
- `connectors`
- `category`
- `review_cadence`
- `target`
- `vision`

If the request attempts to modify any of those fields, reject the call.

### Step 4: Wire scheduled `project_checkin` runs to the new tool

Update the `project_checkin` execution path so that if the scheduled run wants
to record something about a plan, it must use the new narrow tool instead of
`plan_upsert`.

The intended behavior is:

1. read current plans
2. summarize priorities / wins / blockers / next action
3. optionally record a lightweight progress update
4. never rewrite plan structure

### Step 5: Add a defensive merge-preservation safeguard

Patch the plan persistence/update logic so partial updates cannot erase rich
structured fields.

When a plan update payload omits any structured section, the existing stored
value must be preserved.

Specifically:

- omitted arrays must not become empty arrays
- omitted strings must not become empty strings
- omitted nested structures must not become zero values

Only explicitly provided fields may be changed.

This safeguard is required even after removing `plan_upsert` from scheduled
check-ins.

### Step 6: Add regression tests

Add tests that prove all of the following:

1. A rich plan with milestones/tasks/metadata survives a scheduled
   `project_checkin` run unchanged.
2. Scheduled `project_checkin` runs do not have access to generic `plan_upsert`.
3. The new dedicated scheduled progress tool can update allowed lightweight
   fields without modifying plan structure.
4. Partial plan updates do not erase existing structured fields in persistence.
5. A deliberate full structured plan import or normal explicit user plan edit
   still works.

### Step 7: Preserve current product behavior

Do not break:

- plan import
- plan export
- explicit user plan edits from chat or dashboard
- plan dashboard rendering
- scheduled notifications

The only behavior being removed is destructive plan mutation from recurring
project-manager runs.

## Acceptance Criteria

The task is complete only when:

1. rich plans remain rich after repeated scheduled `project_checkin` runs
2. mobile and web planning views still show milestones and tasks after check-ins
3. scheduled check-ins still generate useful summary notifications
4. tests cover the bug and the fix
5. the implementation enforces this in code, not just in prompts

## Non-Negotiable Constraints

- Do not leave generic `plan_upsert` available to `project_checkin`
- Do not depend on the model “doing the right thing”
- Do not erase structured fields on partial updates
- Do not redesign the UI as part of this fix
- Do not make unrelated refactors

