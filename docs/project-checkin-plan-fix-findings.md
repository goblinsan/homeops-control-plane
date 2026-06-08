# Project Check-In Plan Fix Review Findings

This document captures the remaining issues after a partial fix was applied to
`agent-service` for the scheduled `project_checkin` plan-clobber regression.

## Context

The original bug was that recurring `project_checkin` runs were overwriting rich
plans with partial low-fidelity content, which made mobile and web planning
views appear empty or nearly useless.

A follow-up implementation was attempted. It added a new tool named
`plan_progress_update` and denied `plan_upsert` for `project_checkin` runs in
the automation tool policy.

That work is not complete. Two critical issues remain.

## Finding 1

The scheduled prompt still instructs the model to use the wrong tool.

Current file:

- `agent-service/internal/tools/schedules.go`

Current problem:

- `defaultProjectCheckinPrompt(...)` still tells the model to update plans using
  `plan_upsert`

Why this matters:

- New `project_checkin` schedules will continue to embed the stale destructive
  instruction
- this directly contradicts the new tool-policy restriction and the intended
  `plan_progress_update` behavior
- it creates prompt / policy mismatch and keeps the system brittle

Required fix:

- change the scheduled check-in prompt text so it no longer references
  `plan_upsert`
- explicitly instruct scheduled check-ins to use `plan_progress_update` if a
  lightweight plan update is needed
- add or update tests so this prompt text is covered

## Finding 2

The required persistence-layer safeguard was not implemented.

Current files:

- `agent-service/internal/tools/plans.go`

Current problem:

- `PlanProgressUpdateTool` preserves structure for its own writes because it
  loads the existing plan first
- but `PlanUpsertTool` is still unchanged and still builds a fresh
  `store.UserPlan` from only the supplied params
- that means any caller that reaches `plan_upsert` with a partial payload can
  still erase omitted milestones, tasks, metrics, cadence, supporting sections,
  and other structured fields

Why this matters:

- the original product requirement was not just “make check-ins use a safer
  tool”
- it was also “partial plan updates must not clobber structured plans”
- without this safeguard, the bug can reappear through any future path that
  reaches `plan_upsert`

Required fix:

- implement merge-preserving behavior in the plan update path
- omitted structured fields must preserve the currently stored values
- only explicitly provided fields may overwrite existing stored fields

This applies at minimum to:

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

## Required Next Actions

The next implementation pass in `agent-service` must do all of the following:

1. Update the scheduled `project_checkin` prompt in `schedules.go` to reference
   `plan_progress_update` instead of `plan_upsert`
2. Add regression coverage for that prompt / check-in behavior
3. Implement merge-preserving update behavior for partial plan writes in the
   general plan update path
4. Add regression tests proving partial updates no longer erase structured plan
   fields

## Completion Standard

Do not consider the fix complete until:

1. the scheduled prompt no longer references `plan_upsert`
2. partial updates cannot erase rich plan structure
3. tests cover both of those guarantees

