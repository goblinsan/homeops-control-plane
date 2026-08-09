# Autonomous Workforce Discovery

This document captures the current state of the `project-dashboard`,
`task-flow-conductor`, `agent-service`, and `homeops-control-plane` repositories
for turning the existing local coding system into a portfolio execution system.

It is intentionally public-safe. It does not include private topology,
credentials, hostnames, LAN addresses, deployment endpoints, bucket names, or
secret material.

## Scope

Inspected repositories:

- `project-dashboard`
- `task-flow-conductor`
- `agent-service`
- `homeops-control-plane`

Requested target constraint:

- do not create a separate project registry or work-manager service
- `project-dashboard` remains the durable source of truth
- `task-flow-conductor` remains the scheduler and dispatcher
- `agent-service` is reused where it fits
- Forgejo becomes the preferred SCM execution target

## 1. Current Project And Repository Schema

`project-dashboard` owns the current project and repository records in Postgres.

Current `projects` table:

- `id`
- `name`
- `slug`
- `description`
- `created_at`
- `updated_at`

Current `repositories` table:

- `id`
- `project_id`
- `url`
- `default_branch`
- `created_at`
- `updated_at`
- unique constraint on `(project_id, url)`

The repository model is deliberately small today. It knows the remote URL and
default branch, but does not yet store execution metadata such as write policy,
SCM provider, PR policy, migration status, default workflow profile, concurrency
limits, or premium execution policy.

`project-dashboard` also exposes project languages through status/details
responses used by the conductor, but the core repository table is not yet a
portfolio execution registry.

## 2. Current Task And Run Lifecycle

Current task lifecycle is status-based.

Allowed `tasks.status` values:

- `open`
- `in_progress`
- `in_review`
- `blocked`
- `done`
- `archived`

Important task fields:

- `project_id`
- `milestone_id`
- `parent_task_id`
- `title`
- `description`
- `priority_score`
- `external_id`
- `labels`
- `blocked_dependencies`
- `claimed_by`
- `claimed_at`
- review status fields for QA, code, security, and DevOps
- `completed_at`

`task-flow-conductor` currently:

- fetches tasks for a project
- treats `open` and `in_review` as actionable
- prioritizes by `priority_score`, then status-derived priority, then position
- atomically claims a task by patching it to `in_progress`
- processes blocked task dependencies before parent tasks
- adopts orphaned `in_progress` tasks on startup
- marks tasks failed or blocked through dashboard updates when workflows fail
- marks tasks done after the existing workflow reaches its merge-complete point

Current run lifecycle in `project-dashboard` is project-scoped rather than
task-attempt scoped.

Current `runs` fields:

- `id`
- `project_id`
- `external_id`
- `workflow_type`
- `status`
- `source`
- `model_profile`
- `metadata_json`
- `started_at`
- `completed_at`
- `updated_at`

Allowed `runs.status` values:

- `running`
- `completed`
- `failed`
- `cancelled`

Current `run_events` fields:

- `run_id`
- `event_id`
- `sequence`
- `event_type`
- `step_name`
- `status`
- `schema_version`
- `duration_ms`
- `payload_json`

`task-flow-conductor` starts a coordinator run in `project-dashboard`, emits
task start/end events, and completes the coordinator run. This gives useful run
history, but it does not yet persist one durable execution-attempt chain per
task with backend, model, selection reason, parent run, validation result, cost,
PR metadata, and artifacts.

## 3. `POST /plans/evaluate` Contract

`project-dashboard` exposes:

- `POST /plans/evaluate`
- `POST /plans/audit`

Input for `/plans/evaluate`:

- `tasks`, required array of 1 to 500 task drafts
- optional `profile`

Each task draft supports:

- `id`
- `title`
- `description`
- `files`
- `dependsOn`

The default profile is currently labeled `local-14b` and encodes these limits:

- maximum files per task
- maximum unspecified integrations
- premium integration threshold

Output:

- `profile`
- `overallRisk`
- `summary`
- `tasks`

Each evaluated task returns:

- `id`
- `title`
- `risk`: `low`, `medium`, or `high`
- `verdict`: `fits`, `risky`, or `too_hard`
- `routing`: `local-small`, `local-14b`, or `premium-delegate`
- `reasons`
- `suggestions`
- `signals`

Current signal extraction detects:

- file count
- dependency count
- whether import contracts are present
- whether inline types are declared
- integration surface
- design task shape
- whether design tokens/specs are supplied
- whether design derivation is required

The current contract is useful for Phase 5 policy because it already separates
local-fit work from work that should be delegated to a premium model. It is not
yet connected to durable backend-selection records.

## 4. `tasks:bulk` Contract

`project-dashboard` exposes:

- `POST /projects/:projectId/tasks:bulk`

Input:

- body must contain `tasks`
- `tasks` must be a non-empty array
- maximum 100 tasks per call

Each task uses the normal task-create schema:

- `title`, required
- `description`
- `milestone_id`
- `parent_task_id`
- `status`
- `priority_score`
- `external_id`
- `labels`
- `blocked_dependencies`

Behavior:

- inserts tasks inside one transaction
- skips existing tasks with duplicate `external_id`
- returns `created`, `skipped`, and `summary`

Current response summary:

- `totalRequested`
- `created`
- `skipped`

This is already a good idempotent plan-ingestion boundary. Missing pieces for
portfolio execution are execution-policy fields, repository selection, workflow
profile defaults, and richer task/run linkage.

## 5. Workflow Profile Model

`project-dashboard` has a first-class `workflow_profiles` table and routes.

Current fields:

- `workflow_type`
- `description`
- `allowed_file_types`
- `required_tools`
- `validation_commands`
- `expected_artifacts`
- `model_tier_requirement`
- `failure_policy`
- `metadata_json`

Allowed `failure_policy` values:

- `retry`
- `escalate`
- `block`
- `defer`

The conductor already selects workflow YAML by task type/scope/status, but
workflow profiles are not yet the primary scheduler contract. The target system
should use workflow profiles as policy inputs instead of adding a parallel
classification system.

## 6. Capability Tier Derivation

`project-dashboard` has `benchmark_results` and derived `capability_tiers`.

`POST /capability-tiers/derive`:

- aggregates `benchmark_results` where `scope = 'workflow'`
- optionally filters by benchmark suite
- joins workflow profile requirements
- computes pass rate
- applies configurable pass threshold and minimum sample count
- upserts by `(model_id, workflow_type, language)`

Current verdicts:

- `qualified`
- `unqualified`
- `insufficient_data`

Current derived fields:

- `model_id`
- `workflow_type`
- `language`
- `required_tier`
- `achieved_tier`
- `pass_rate`
- `sample_count`
- `verdict`
- `evidence_json`

This is directly reusable for backend selection. It should become one of the
primary inputs to local-vs-premium routing.

## 7. Benchmark Result Model

Current `benchmark_results` fields:

- `run_id`
- `external_id`
- `benchmark_suite`
- `benchmark_case`
- `scope`
- `workflow_type`
- `language`
- `model_id`
- `node_id`
- `pass`
- `score_json`
- `metrics_json`
- `created_at`

Allowed scopes:

- `model`
- `workflow`

Routes support:

- creating benchmark results directly
- attaching benchmark results to a run
- listing/filtering benchmark results
- summary aggregation by model, workflow type, and scope

JSON score/metrics payloads are size-capped to discourage raw logs or secret
material. This model is suitable as the evidence store for capability policy,
but it does not yet record per-task execution outcomes in enough detail for
escalation auditing.

## 8. Existing Agent Dispatch Implementation

`task-flow-conductor` dispatches local model calls through persona execution.

Current dispatch path:

- workflow YAML step
- persona request step
- `dispatchPersonaRequest`
- `PersonaRequestExecutor`
- context extraction and message formatting
- local LM Studio/OpenAI-compatible call

Current local model behavior:

- configured by persona in environment-derived config
- calls an LM Studio-compatible `/v1/chat/completions` endpoint
- supports structured response formats when configured
- has timeout and retry logic
- has an LM Studio circuit breaker

There is no provider-neutral execution backend interface today. Local execution
is embedded in persona request execution. Claude/Codex-specific behavior is not
currently isolated behind a backend contract.

`agent-service` has a separate model-routing system:

- model provider interface
- prefix-based router
- multi-node local model registry and pool
- persisted chat and automation runs
- tool execution and approvals
- scheduling and notification support

That is reusable for general agent/model orchestration, but it is not the
current coding-work scheduler and should not replace `project-dashboard` or
`task-flow-conductor`.

## 9. Existing SCM/Git Integration

`task-flow-conductor` has substantial git primitives.

Current capabilities include:

- resolving repo roots from payload/dashboard metadata
- cloning or reusing repositories under `PROJECT_BASE`
- detecting default branch
- checking out branches from a base branch
- checking context freshness
- committing selected paths
- pushing branches
- ensuring a branch is published
- verifying a remote branch has a diff from base
- syncing a branch with base for preflight
- merging a branch into a target branch
- guarded workspace mutation
- git identity setup for machine commits
- SSH known-host and key configuration

Current workflows use these primitives to:

- create task or milestone branches
- commit implementation and review artifacts
- push branches
- validate branch diff
- perform pre-merge checks
- merge branches back to `main`

The current happy path conflicts with the requested safety model because it
merges to `main`. The target system must replace final merge steps with a
review-ready branch plus Forgejo PR creation.

## 10. Current Forgejo Integration

`homeops-control-plane` inventory and public-safe runbooks show Forgejo is live
and already used for selected operational repositories.

Current state:

- Forgejo is an internal git forge with backup coverage.
- Some operational repositories are already Forgejo-backed.
- `project-dashboard` and `task-flow-conductor` are documented as auto-deploying
  from Forgejo `main` pushes.
- `gateway-control-plane` is documented as Forgejo-backed for source and
  auto-deploy.
- Some newer operational repos are documented as Forgejo repositories but still
  have manual deployment gaps.
- Several older or adjacent projects remain GitHub-backed or have no remote.

`task-flow-conductor` itself does not currently include a Forgejo API client or
Forgejo pull-request creation step. It has provider-neutral git push behavior,
but no SCM provider abstraction for PR creation.

`homeops-control-plane` includes a generic Forgejo/Gitea repository creation
script and runbooks that recommend Forgejo as the first step for new private
operational repos.

## 11. Artifact And Run Result Persistence

`project-dashboard` artifacts:

- can be project-level or task-level
- include `kind`, `content`, `content_hash`, `byte_size`, `iteration`, and
  `workflow_id`
- are upserted by `(project_id, task_id, kind, iteration)`
- can be fetched with `latest` and `meta_only`

`task-flow-conductor` uses `ArtifactAPI` to publish and fetch artifacts. It also
commits `.ma` artifacts into work branches for implementation context, reviews,
and QA traces.

Run result persistence today:

- dashboard run records hold coordinator-level run metadata
- dashboard run events record task start/end and step-level events
- benchmark results can attach to a run
- conductor logs remain process-local or service-local
- artifact content lives in dashboard artifact rows and/or committed `.ma`
  files

Missing for the target system:

- durable task attempt table or equivalent relation
- parent-child run chain for local-to-premium escalation
- backend and model fields per attempt
- decision reason and policy inputs per backend selection
- failure category per attempt
- validation output per attempt
- token/cost metadata per attempt
- branch and PR metadata per attempt/task
- first-class `REVIEW_READY` disposition

## Key Gaps

- Repository records need execution policy metadata, but only as extensions to
  the existing repository/project models.
- Task status lacks an explicit review-ready terminal-for-automation state.
- Runs are project-scoped and not sufficiently linked to task attempts.
- Backend selection is implicit in local persona config, not durable policy.
- There is no provider-neutral execution backend contract.
- There is no Forgejo PR creation adapter.
- The current conductor happy path merges to `main`, which is disallowed by the
  requested safety model.
- Existing dashboard views are API-oriented; portfolio execution views need new
  read models or endpoints.
- Premium-use policy does not exist yet.

## Reusable Strengths

- `project-dashboard` already has the correct durable center: projects, repos,
  tasks, artifacts, runs, workflow profiles, benchmark results, and capability
  tiers.
- `task-flow-conductor` already has task claiming, dependency ordering, workflow
  YAML, model/persona execution, git branch/push support, validation gates, and
  run-event persistence.
- `agent-service` already has model routing, multi-node local model pooling,
  persisted agent runs, approvals, tools, schedules, notifications, and metrics.
- `homeops-control-plane` already defines public-safe operational conventions,
  Forgejo creation workflow, and deployment/backup guardrails.

## Discovery Conclusion

The system is close to the requested architecture but needs a policy and
persistence layer, not a new service. The correct next move is to extend
`project-dashboard` with portfolio execution metadata and attempt history, then
teach `task-flow-conductor` to select provider-neutral execution backends and
stop at Forgejo PR review rather than merging to `main`.
