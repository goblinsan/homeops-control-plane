# Distributed System Agent Handoff

This document is the public-safe handoff for agents continuing work on the HomeOps distributed system.

It intentionally avoids real topology, credentials, bucket names, LAN addresses, and service-to-host mappings.
Real environment state belongs only in the local encrypted inventory and local-only handoff files.

## Purpose

Use this document to understand:

- the current control-plane strategy
- the repo relationships
- what has already been completed
- what remains to reach a working distributed system
- how to continue safely without leaking private topology into Git

## Safety Boundaries

Never commit any of the following:

- real node names
- real LAN IPs
- SSH usernames tied to real hosts
- service placement details
- object-storage locations
- API tokens, admin tokens, credentials, or secret-bearing config

Use the local encrypted inventory for all real environment data:

- `.inventory/nodes.yaml`
- `.inventory/repos.yaml`
- `.inventory/services.yaml`
- `.inventory/backups.yaml`

Use the local-only supplement at `.inventory/agent-handoff.local.md` for concrete operational state.

## Control Model

The intended model is:

1. `homeops-control-plane` is the orchestration index and runbook repo.
2. Real topology lives only in the encrypted local inventory and S3 bundle.
3. Service repos remain the source of truth for deployable code.
4. Commits and pushes should drive deploys through the existing local GitHub Actions runner topology where available.
5. New nodes may require one-time manual bootstrap before they can participate in the standard pull/deploy flow.

This repo should describe:

- what nodes and services exist in abstract
- what repos correspond to what workloads
- what deployment pattern each repo uses
- what operational runbooks and validation steps are required

This repo should not become the transport mechanism for service code.

## Related Repositories

The current system spans multiple repos, including:

- `homeops-control-plane`
- `gateway-control-plane`
- `gateway-api`
- `gateway-chat-platform`
- `gateway-tools-platform`
- `stt-service`
- `cv-sam-service`
- `llm-service`
- `local-tts-service`
- `agent-service`
- `gh-project-helper`
- `GatewayApp` as a local-only companion app

There are also adjacent repos that should stay indexed because they matter operationally or strategically, even if they are not always deployed as services.

## Completed Work

### Post-merge stabilization of delegated planning work

Completed after reviewing the merged delegated work in `gateway-chat-platform`
and `agent-service`:

- `gateway-chat-platform` commit `d6540f2`:
  - the visual plan tracker no longer writes to a chat-api-local Prisma plan
    store
  - plan CRUD routes now proxy through `agent-service /internal/plans`
  - this removes the split-brain where the UI and the assistant could see
    different plan state
- `agent-service` commit `e43c413`:
  - accidental tracked build artifact removed from the repo
  - duplicated migration numbering cleaned up by renaming the hierarchy
    migration to `012_user_plan_hierarchy.sql`
- `gateway-chat-platform` commit `c687b01`:
  - the shared iOS package now owns the persisted-session bootstrap flow used
    by the local `GatewayApp` companion app
  - session state loads asynchronously instead of doing token/config reads on
    the initial path
- `agent-service` commit `bc2eaa1`:
  - APNs delivery client now explicitly attempts HTTP/2, which matches the
    transport expectations of the Apple push endpoint

Operationally important result:

- the merged plan-tracker feature now points at the same durable `user_plans`
  store used by agent orchestration and project-manager context assembly
- both repos were cleaned to a zero-diff working-tree state after the
  stabilization commits landed

### Inventory bootstrap

Completed in this repo:

- encrypted inventory bootstrap flow
- local inventory initialization helper
- schemas for nodes, repos, services, and backups
- healthcheck validation for repo structure
- secure inventory runbook updates

### Inventory population

Completed locally:

- real node inventory populated
- real repo inventory populated
- real service inventory populated
- local-only planning notes for pending services added

Real values are intentionally excluded from the tracked repo.

### Control-plane UI hardening

Completed in `gateway-control-plane`:

- default admin config responses now redact secrets
- secret values are no longer shipped to the browser by default
- reveal behavior now requires explicit fetch of the full config
- save path preserves stored secrets when redacted placeholders are submitted back

This work was validated locally with typecheck and tests before deployment.
It has now also been committed, pushed, and deployed through the normal
gateway blue/green workflow.

### GPU node bootstrap

Completed operationally on the new GPU node class:

- Debian workstation conversion brought to a usable server baseline
- Docker runtime verified
- NVIDIA driver installed successfully
- NVIDIA container toolkit installed successfully
- GPU visibility confirmed on host and in containers
- `llm-service` successfully built and started with a newer CUDA toolchain

### `llm-service` runtime portability

Completed in `llm-service`:

- mixed-runtime support pushed to GitHub
- CUDA base images are now explicit runtime knobs
- per-node CUDA architecture override remains supported
- default CUDA image line moved forward enough to support newer GPU generations

This keeps one repo usable across multiple node classes instead of forcing node-specific code forks.

### `local-tts-service` bootstrap

Completed operationally:

- service deployed from GitHub on the new GPU node
- isolated Python `3.11` runtime created with `uv`
- systemd service installed
- health endpoint verified
- runtime endpoint verified with CUDA-enabled Torch

### Control-plane runtime verification

Completed operationally:

- the gateway control-plane blue/green deploy workflow completed successfully
- the updated admin UI bundle is serving on the active slot
- the new masked-secret placeholder behavior is present in the live rendered UI
- worker-node and remote-workload config was inspected directly on the deployed host
- shared Postgres and Redis ports on the core data-service host were confirmed reachable from the gateway host

### Cross-surface chat sync groundwork

Completed in `gateway-chat-platform`:

- web chat threads were switched from browser-local persistence to the server-backed `/api/threads` API
- web thread summaries now load from the backend and thread message history hydrates on demand
- browser and native-app identity resolution was updated so single-user deployments can map the web session and mobile token to the same stable server-side thread owner

This work has been committed and pushed through the normal deploy-on-merge flow.
Follow-up live verification is still required.

### Scheduled work and notification inbox foundation

Completed and pushed to `main`:

- `agent-service` commit `98bc064` adds:
  - scheduled-job persistence and worker polling loop
  - notification persistence APIs
  - device-token persistence APIs
  - API handlers for notifications, schedules, and device tokens
- `gateway-chat-platform` commit `88c9436` adds:
  - chat API proxy routes for notifications, schedules, and devices
  - inbox hook migration to server-backed notification feed

Scope note:

- unrelated in-progress iOS refactor changes were intentionally kept out of this feature commit set

### Scheduler and push follow-up fixes

Completed and pushed to `main`:

- `agent-service` commit `72abed9` adds:
  - correct terminal state handling for failed one-shot scheduled jobs
  - safe recurring-job reschedule handling so invalid recurrence strings disable the job instead of hot-looping forever
  - notification listing that excludes dismissed inbox items
- `gateway-chat-platform` commit `6ccaa70` adds:
  - mirroring from the existing mobile APNs registration route into `agent-service` device-token storage
  - web inbox mapping that respects read state and filters dismissed notifications defensively

Already completed earlier:

- `gateway-chat-platform` commit `144f4b4` makes the `chat-api` to `agent-service` Docker network relationship durable in compose so container recreation does not break `agent-service` hostname resolution

### Reminder delivery and inbox hardening

Completed and pushed to `main`:

- `agent-service` commit `fe14864` adds:
  - a first-class schedule-creation tool for reminder requests
  - reminder guidance so the model uses scheduling instead of abusing memory tools
- `agent-service` commit `980cffa` adds:
  - automation routing fallback to the normal chat node when no dedicated automation node is configured
  - this prevents scheduled reminder runs from failing solely because automation-specific routing is unset
- `gateway-chat-platform` commit `8914c29` adds:
  - defensive normalization of notification records returned from `agent-service`
  - web inbox rendering that tolerates notification records even when older payloads are inconsistent
  - the shared iOS package inbox surface wired to the same `/api/notifications` feed used by the web inbox
- `agent-service` commit `0527f2b` adds:
  - a reminder-job policy that blocks `create_schedule` during reminder execution
  - this prevents one-shot reminders from recursively creating fresh reminder jobs when they fire
- `agent-service` commit `528e977` adds:
  - deterministic reminder delivery that no longer uses free-form assistant output as the notification body
  - reminder notifications now use the reminder text itself and the title `Reminder`
  - this removes the class of bugs where reminder notifications talk about scheduling the reminder instead of delivering it

Operational status:

- the `gateway-chat-platform` deploy-on-merge run for `8914c29` completed successfully
- the `agent-service` fixes were pulled and rebuilt live on the gateway host
- a local rebuild/relaunch of the companion iPhone app is still required to confirm APNs re-registration through the corrected app-target path

### Mobile planning tab redesign and deploy/auth stabilization

Completed in `gateway-chat-platform` and `gateway-control-plane`:

- the iPhone Planning tab was redesigned from a compact tracker into a
  multi-screen planner built around mobile navigation instead of dense web-style
  layout
- the main Planning view now exposes day, week, month, and year horizons with
  date navigation
- task progress now uses the requested workflow order:
  `todo`, `in_progress`, `complete`, `on_hold`, `blocked`
- shared plan contracts now distinguish task statuses from higher-level plan and
  milestone status values, avoiding the earlier mismatch between task progress
  and goal health
- plan, milestone, project, and goal detail flows were added so a user can drill
  into a milestone or owning project/goal instead of only seeing a flat task list
- plan-detail sections are now editable and collapsible, with headings treated as
  their own editable/collapsible section rather than static text embedded in the
  body
- the shared iOS client and local `GatewayApp` wrapper were updated to match the
  new plan APIs and task-status model
- iOS package CI now builds/tests the shared mobile package so Planning tab
  changes get checked before merge
- chat-platform deploy-on-merge now runs the broader workspace typecheck before
  deployment, catching cross-package type drift before production rollout

Operational follow-up completed in `gateway-control-plane`:

- the chat API mobile auth path was confirmed to remain bearer-token first for
  native clients, independent of the browser Cloudflare Access flow
- chat-platform env generation now preserves existing non-empty mobile bearer
  token secrets across deploys, including token rotation values even when the
  rendered service profile omits the rotation key
- a recovery workflow can merge mobile bearer tokens found in the live shared env
  and host-side deployment/config work directories without logging token values
- the recovery workflow redeploys chat-platform and verifies every configured
  mobile bearer token against `/api/session/me` before reporting success

Current status:

- the mobile Planning tab redesign has been committed and pushed
- follow-up fix `cad67c8` corrected the mobile horizon implementation so the
  default day view no longer shows every active task
- follow-up fix `819aaa8` corrected weekday matching in the mobile planner so
  imported plans with English weekday-prefixed task titles still match the
  selected day even when the device locale differs
- delete and `Won't do` task actions are now available directly in the mobile
  planner and task-detail flows
- deploy preservation and recovery verification have been committed, pushed, and
  run successfully
- remaining validation is user-facing: open the local companion app and confirm
  the redesigned Planning tab and existing mobile token both work as expected

Known limitation:

- the current task model still has no explicit date fields
- day/week filtering is heuristic for now:
  - it matches weekday-prefixed task titles such as `Monday: ...`
  - it can also infer weekdays from plan cadence metadata when task or
    milestone text matches the cadence activity
- if true calendar scheduling is required, the next schema change should add
  explicit task timing fields such as `scheduled_for`, `start_at`, or `due_at`

## Current Architecture Direction

The intended distributed pattern is:

- one or more LLM nodes with different model sizes and capacities
- one local TTS node
- a control plane for service deployment and operational visibility
- a chat/API layer that calls into the model and voice services
- a future `agent-service` that owns orchestration, model routing, and tool-execution loops

`agent-service` should be treated as the next major integration point.

## New Near-Term Priority

The current next operational goal is to turn the additional storage attached to
the Papai node into network-accessible household storage.

Recommended direction:

- use SMB as the primary protocol first
- target compatibility with:
  - macOS Finder clients
  - Windows Explorer clients
- defer any NFS-only optimization until the SMB path is stable

Immediate work still needed:

1. inspect the live Papai disk and mount layout
2. define the intended share boundaries and access model
3. configure Samba on Papai
4. verify client mounting from macOS and Windows
5. add a public-safe runbook to this repo documenting the generic SMB setup

## Remaining Work

### Workstream 1: finish node rollout

- bring the remaining planned LLM nodes onto the updated `llm-service` repo state
- confirm their per-node CUDA/runtime settings
- verify health and `/api/node` metadata on each node
- register each node cleanly in the control-plane model
- ensure each node has the intended model artifact loaded, not just a healthy wrapper service

### Workstream 2: validate and enable scheduled-work delivery

The recommended role for `agent-service` is:

- orchestrator across multiple `llm-service` nodes
- owner of tool-execution loops
- consumer of shared Postgres and Redis services
- backend used by chat-facing services for structured agent work

Still needed:

- verify the phone rebuild/relaunch re-registers the APNs token through the corrected client path
- create a fresh reminder after the latest deploys and confirm it appears in the web inbox without rendering errors
- confirm the same reminder appears in the iPhone in-app inbox surface and reaches the device as a push
- verify scheduled jobs create notifications at the expected times without duplicate or stuck re-runs
- verify reminder notifications now contain the actual reminder text rather than scheduling-related assistant prose
- keep delivery telemetry and failure handling for invalid or expired push tokens under observation during rollout

Known behavior:

- notification bodies are intentionally capped at `280` characters in the scheduler worker before push/inbox fan-out
- recurring schedules are supported today as interval-based recurrence strings such as `@every 24h`
- recurring schedules now also support timezone-aware local daily windows via `@daily-local HH:MM[,HH:MM...]` plus a stored IANA timezone
- invalid recurrence strings are now disabled safely instead of hot-looping

Recommended immediate next item:

- validate end-to-end reminder delivery from chat request to scheduled execution to inbox/push, then broaden scheduled work usage

### Workstream 2a: evolve scheduled work into project-manager check-ins

The target user-facing behavior is:

- the system should act as a project manager
- it should check in on a regular cadence
- it should give guidance tied to stated goals and current progress
- it should update progress against those goals over time

Current platform fit:

- the notification, inbox, and schedule foundation now exists
- the user-plan and memory primitives already exist in `agent-service`
- recurring schedules can already drive interval-based follow-ups

What is still needed for the full project-manager loop:

- live validation of the new dedicated check-in job path rather than treating everything as a generic reminder
- live validation of wall-clock recurrence so morning, afternoon, and night check-ins execute at the intended local times
- a write-back path that lets the system record progress updates, next steps, and unresolved blockers against the user’s plans
- inbox and push UX that distinguishes reminders from project-manager check-ins

Near-term implementation path:

- deploy and validate the new `project_checkin` scheduled-job kind
- deploy and validate multiple named local-time schedule windows
- have each check-in run read `user_plans`, recent events, and relevant memory before composing the guidance message
- append a structured progress note or plan update after each completed check-in when appropriate

Latest progress:

- `agent-service` now has a `plan_ingest_text` tool so pasted plain-text or markdown plans from other systems can be converted into durable `user_plans`
- user-context injection now includes plan-step detail, not just top-level plan titles and summaries
- user-context guidance now explicitly tells the model to call `plan_list` early for project-manager-style guidance and to use `plan_ingest_text` when the user pastes a roadmap or plan document
- the iPhone notification inbox now has an on-demand `Read aloud` action that sends notification text through the existing gateway TTS path
- `user_plans` has been extended in code with typed metadata fields: `category`, `tags`, `data_sources`, `review_cadence`, and `metrics`
- `plan_upsert`, `plan_list`, and `plan_ingest_text` now understand and return that typed metadata so future domain-specific workflows can distinguish work, health, finance, and social plans
- the iPhone chat surface now has a document-import flow for plain-text and markdown files; imported text is prefixed with an explicit `plan_ingest_text` instruction so users can ingest external plans without retyping them
- `agent-service` now has a dedicated `create_project_checkin` tool that schedules recurring `project_checkin` jobs against named daily windows (`morning`, `afternoon`, `night`)
- the scheduler now supports timezone-aware daily wall-clock recurrence using an IANA timezone plus `@daily-local` recurrence strings
- `project_checkin` and `reminder` automation runs are both prevented from recursively scheduling more future jobs
- the delegated visual plan tracker work was reviewed and stabilized so it no longer writes to a second chat-api-local plan store
- `gateway-chat-platform` now proxies tracker CRUD through `agent-service /internal/plans`, keeping the assistant and UI on the same durable plan source of truth
- repository cleanup after that review removed an accidental committed `agent-service` binary and renumbered the duplicated hierarchy migration to `012_user_plan_hierarchy.sql`

What still needs live validation:

- verify the tracker on the live web UI and the iPhone app still behaves correctly after the `agent-service` plan-route unification
- confirm creating or editing milestones/tasks in the tracker changes the same plan state later used by project-manager check-ins and reminder context
- decide whether any legacy chat-api-local plan rows need one-time cleanup or migration, or whether they can simply be abandoned

### Workstream 2b: finish the plan-tracker product loop

The storage and CRUD plumbing now points at the durable plan store, and the
mobile Planning tab has moved to a more complete multi-screen workflow.

Recently completed:

- iPhone Planning now opens on a day-focused task view instead of a generic
  tracker overview
- secondary mobile views cover week, month, and year planning horizons, with
  previous/next navigation for each horizon
- task status updates use the mobile workflow order `todo` -> `in_progress` ->
  `complete` -> `on_hold` -> `blocked`
- delete and `Won't do` actions are available in the mobile planner and
  task-detail surfaces
- detail screens exist for milestones and owning project/goal context
- editable/collapsible detail sections were added so plan headings, notes, and
  related metadata can be managed without overloading the task list
- the web/shared/mobile plan types now use task-specific status values for tasks
  and health-style status values for goals/milestones

Still needed:

- verify the live web tracker and local iPhone tracker both read and mutate the
  same `agent-service` plan records
- validate the redesigned mobile Planning navigation on an actual device after
  the latest deploy/auth fixes
- decide whether task scheduling should stay heuristic or whether explicit
  date/timeline fields should be added to the shared plan schema
- decide whether plan review cadence, next-review timing, and typed metadata
  should be editable directly in the tracker views rather than only through
  backend tools
- ensure project-manager check-ins write progress back into those same plans so
  the tracker becomes the visible state surface for the assistant’s ongoing work

### Workstream 3: fold the new node into normal deploy flow

Current node bootstrap was partly manual. The next step is to make it first-class:

- confirm how the repo should be pulled on the node
- decide whether the node needs a self-hosted runner or only receives deploy artifacts
- wire it into the existing push-to-deploy expectations

### Workstream 4: deploy hygiene and observability

Still needed:

- verify health and logs across all active services
- confirm restart policy and persistence layout
- improve telemetry for node and workload status
- confirm backup coverage for service state and model assets where required

### Workstream 5: finish cross-device chat sync verification

The key design split has now been removed in code, but live validation still remains:

- confirm the deployed web chat surface shows the same server-backed threads as the mobile app
- confirm opening a thread in web hydrates message history correctly
- confirm new messages sent from web appear in the mobile app and vice versa
- if the live chat UI still shows `fetch failed`, identify whether the failure is on initial thread-list load, thread-detail load, or send/stream
- keep in mind that a single-user deployment currently depends on identity unification between browser and mobile surfaces

### Workstream 6: control-plane deploy of the secret-redaction fix

The `gateway-control-plane` fix must be carried through:

- verify in the live admin UI that secrets are redacted by default

The commit/push/deploy steps are now complete. Remaining work is only follow-up
verification and keeping the fix intact through future changes.

## Goal-System Roadmap

The near-term implementation order for the project-manager assistant is now:

1. typed plan metadata

- status: implemented in code
- purpose: let the system tell the difference between work, health, finance, and social goals
- shape: `category`, `tags`, `data_sources`, `review_cadence`, `metrics`

2. plan-document import from mobile

- status: implemented in code
- current UX: import a plain-text or markdown file from the iPhone app, prefill chat with a `plan_ingest_text` instruction, then send it
- limitation: there is not yet a first-class attachment transport or background ingest API; the flow still routes through chat intentionally

3. recurring project check-ins

- status: not yet implemented
- next requirement: support wall-clock local-time recurrence for named check-in windows such as morning, afternoon, and night
- recommended design: add a dedicated `project_checkin` job type instead of treating check-ins as generic reminders

4. domain/source connectors

- status: not yet implemented
- target examples:
  - health: Apple Health, Strava, LoseIt
  - finance: budget sheets or finance sources
  - social: people/relationship context and reminders
  - work: repos, project docs, and active plans

## Verification Checklist

When continuing work, prefer verifying these surfaces:

- repo health with `./scripts/healthcheck.sh`
- workload health endpoints
- model-node capability endpoints such as `/api/node`
- runtime endpoints for services with GPU or interpreter dependencies
- systemd status for host-managed services
- Docker Compose status for containerized services

Do not assume a service is integrated just because it is running locally on a node.

## Suggested Next Execution Order

1. Verify and roll out the remaining planned LLM nodes.
2. Verify the latest `agent-service` and `gateway-chat-platform` deploys complete cleanly.
3. Confirm the mobile APNs registration route is mirrored into `agent-service`.
4. Create a test notification and verify web inbox plus mobile push delivery.
5. Enable and validate scheduled jobs behind the existing feature flag.
6. Normalize the new node into the standard pull/deploy model.
7. Tighten telemetry, backups, and maintenance routines.
8. Verify the live web/mobile chat surfaces are actually sharing the same server-backed thread list and history.
9. Validate the redesigned mobile Planning tab against live plan data, including today tasks, horizon views, status updates, and detail editing.

Immediate resumption note:

- the planned LLM-node fleet (tiny, small, medium tiers) is now all
  running the same upstream commit of `llm-service`, including a
  recent wrapper fix for an inference-slot leak on the model-rewrite
  proxy path
- the tiny-tier GPU bring-up is complete and serving with full GPU
  offload; the previously needed CPU-only compose override has been
  retired
- one tier-node is currently healthy but `no-model` after redeploy
  and needs its model reloaded before it serves inference again
- `agent-service` is now online; the next concrete task is validating
  inbox and push delivery end to end, then enabling real scheduled work
- the web chat surface has now been migrated in code from browser-local
  thread storage to the server-backed `/api/threads` API, and a follow-up
  identity fix was pushed so web and mobile can resolve to the same
  single-user thread owner
- because of that, the next chat-surface task is live verification:
  reload the deployed web UI, confirm the mobile-created threads appear,
  and if `fetch failed` persists, isolate whether it is the thread-list
  request, thread-detail request, or chat send path
- a follow-up worth tracking: the control-plane is not yet
  reconciling `llm-service` on worker nodes, so node drift requires
  manual redeploy
- the earlier `chat-api` to `agent-service` Docker-network issue is now
  encoded in compose, so future restarts should not require a manual
  `docker network connect` repair

## Local-Only Dependencies

To continue effectively, the next agent will also need:

- the local encrypted inventory contents
- the local-only environment handoff in `.inventory/agent-handoff.local.md`
- access to the relevant service repo checkouts on disk
- access to the authenticated admin UI when control-plane inspection is needed

Without those local-only inputs, an agent can continue public-safe repo work but cannot safely drive the real environment.
