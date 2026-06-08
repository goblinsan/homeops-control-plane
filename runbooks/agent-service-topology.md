# Agent Service Topology

Use this runbook to place and operate `agent-service` as part of the HomeOps stack.

## Recommended Placement

Run `agent-service` on the always-on internal application host rather than on a single GPU worker.

Why:

- `gateway-chat-platform` is the primary caller
- automation callers also need a stable internal endpoint
- the service can route to multiple `llm-service` nodes over LAN using `LLM_NODES`
- the repo’s own deployment guide describes it as an internal-only backend behind another service

## Recommended Topology

```text
client
  -> gateway-chat-platform
  -> agent-service
  -> PostgreSQL
  -> llm-service nodes
```

## Runtime Requirements

Prepare:

- PostgreSQL 14+
- `DATABASE_URL`
- `LLM_NODES`
- optional `API_KEY`
- optional `MCP_ENDPOINT`

Minimum environment:

```text
DATABASE_URL=postgres://<user>:<pass>@<host>:5432/<db>?sslmode=require
LLM_NODES=http://<llm-node-a>:8080,http://<llm-node-b>:8080
API_KEY=<shared-internal-key>
```

## Deployment Shape

A simple first deployment is Docker Compose with:

- one `agent-service` container
- one PostgreSQL container or a managed/shared PostgreSQL instance
- an internal-only bind or reverse proxy route

Do not expose `agent-service` directly to the public internet.

## Health Checks

Required checks:

```bash
curl http://<host>:8080/health
curl http://<host>:8080/metrics
```

Then verify end-to-end routing with one internal request that exercises:

1. request acceptance
2. database persistence
3. LLM node selection
4. successful completion

## Inventory Expectations

Record in the local encrypted inventory:

- host node
- service exposure
- dependent repos
- deployment strategy
- LLM node pool membership
