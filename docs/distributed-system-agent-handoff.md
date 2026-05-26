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

## Current Architecture Direction

The intended distributed pattern is:

- one or more LLM nodes with different model sizes and capacities
- one local TTS node
- a control plane for service deployment and operational visibility
- a chat/API layer that calls into the model and voice services
- a future `agent-service` that owns orchestration, model routing, and tool-execution loops

`agent-service` should be treated as the next major integration point.

## Remaining Work

### Workstream 1: finish node rollout

- bring the remaining planned LLM nodes onto the updated `llm-service` repo state
- confirm their per-node CUDA/runtime settings
- verify health and `/api/node` metadata on each node
- register each node cleanly in the control-plane model
- ensure each node has the intended model artifact loaded, not just a healthy wrapper service

### Workstream 2: deploy `agent-service`

The recommended role for `agent-service` is:

- orchestrator across multiple `llm-service` nodes
- owner of tool-execution loops
- consumer of shared Postgres and Redis services
- backend used by chat-facing services for structured agent work

Still needed:

- choose the final deploy host
- verify or provision the required shared Postgres database/user
- deploy the repo from GitHub
- configure upstream callers
- register model-node endpoints
- add APNs dispatch fan-out from `agent-service` notification events to registered device tokens
- add delivery telemetry and failure handling for invalid or expired push tokens

Recommended immediate next item:

- implement APNs delivery in `agent-service` behind explicit environment-gated configuration, keeping scheduler default-off behavior unchanged until rollout validation is complete

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
2. Provision or confirm the shared Postgres database/user required by `agent-service`.
3. Deploy `agent-service` against shared data services.
4. Connect chat/orchestration callers to `agent-service`.
5. Normalize the new node into the standard pull/deploy model.
6. Tighten telemetry, backups, and maintenance routines.
7. Make the `gateway-chat-platform` to `agent-service` network relationship durable so cross-surface thread sync survives container recreation.
8. Verify the live web/mobile chat surfaces are actually sharing the same server-backed thread list and history.

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
- the next concrete task is provisioning the shared database and
  user for `agent-service` and bringing `agent-service` online
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
- a newer operational issue was identified on May 25, 2026: the
  active `gateway-chat-platform` `chat-api` container could not
  resolve `agent-service`, which broke `/api/threads` for the iOS
  app with `502`. The immediate live fix was attaching the active
  green `chat-api` container to `agent-service_default` with alias
  `agent-service`. This restored thread sync but is not durable
  across restart/redeploy until encoded into compose or deployment
  automation

## Local-Only Dependencies

To continue effectively, the next agent will also need:

- the local encrypted inventory contents
- the local-only environment handoff in `.inventory/agent-handoff.local.md`
- access to the relevant service repo checkouts on disk
- access to the authenticated admin UI when control-plane inspection is needed

Without those local-only inputs, an agent can continue public-safe repo work but cannot safely drive the real environment.
