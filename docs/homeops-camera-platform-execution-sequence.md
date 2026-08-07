# HomeOps Camera Platform Execution Sequence

This document turns the camera platform plan into a concrete execution order.

It is intentionally public-safe:

- use placeholders for hosts, tokens, camera paths, and URLs
- do not store real credentials, IP addresses, hostnames, WireGuard keys, or S3
  bucket names here
- keep production values in private inventory, host-managed env files, or the
  approved secret store

## Repository

Create or verify this Forgejo repository first:

- `homeops-camera-platform`

Recommended owner:

- the private operational org or user on the local Forgejo instance

## Forgejo Creation

Use the generic script in this repo:

```bash
export FORGEJO_BASE_URL=http://<forgejo-host>:<port>
export FORGEJO_TOKEN=<forgejo_pat>

./scripts/create-forgejo-repo.sh \
  --owner <forgejo-org> \
  --owner-type org \
  --name homeops-camera-platform \
  --description "Edge-first HomeOps camera platform with Frigate and Scrypted Core"
```

Expected remote pattern:

```text
ssh://git@<forgejo-host>:<ssh-port>/<forgejo-org>/homeops-camera-platform.git
```

## Recommended Implementation Order

### 1. Publish The Scaffold

Use `homeops-camera-platform/` as the seed content for the new repository.

Goal:

- the repo has Phase 0 docs and the Phase 1 edge skeleton
- public-safe scans pass
- no runtime env file is committed

### 2. Choose The Edge Host

Confirm in private inventory:

- edge hardware
- Linux distribution
- management path
- recording disk mount
- camera network reachability
- acceleration hardware, if any

Goal:

- the edge host is known and safe to provision
- destructive disk work, if needed, has an explicit operator confirmation gate

### 3. Materialize Runtime Inputs

Create the edge runtime env file from private sources.

Required categories:

- camera address, stream paths, and credentials
- bind address for Frigate management and restream ports
- site and household IDs
- central API URL
- archive endpoint metadata and credential file references
- timezone and local storage paths

Goal:

- `deploy/edge/.env.example` has a private runtime counterpart on the edge host
- no secret values are printed into logs or chat

Preferred materialization path:

```bash
./scripts/render-edge-runtime.sh \
  --input deploy/edge/runtime.local.json \
  --env-out deploy/edge/.env

./scripts/render-frigate-config.sh \
  --input deploy/edge/runtime.local.json \
  --config-out /srv/homeops-camera/config/frigate/config.yml
```

### 4. Validate Camera And Host

Run:

```bash
./scripts/validate-runtime-env.sh <runtime-env-file>
./scripts/bootstrap-edge.sh
./scripts/validate-camera.sh
./scripts/edge-preflight.sh <runtime-env-file>
./scripts/smoke-test.sh
```

Goal:

- required directories exist
- camera ONVIF and RTSP ports are reachable from the edge host
- Compose and template checks pass

### 5. Start CPU-Only First

Start with the base Compose file:

```bash
docker compose --env-file <runtime-env-file> \
  -f deploy/edge/compose.yaml \
  up -d
```

Goal:

- Frigate records the main stream
- Frigate detects people using the substream
- Scrypted Core provides a live stream
- services recover after container restart

### 6. Add Hardware Acceleration Deliberately

After CPU-only recording works, add one hardware override:

```bash
docker compose --env-file <runtime-env-file> \
  -f deploy/edge/compose.yaml \
  -f deploy/edge/compose.intel-qsv.yaml \
  up -d
```

or:

```bash
docker compose --env-file <runtime-env-file> \
  -f deploy/edge/compose.yaml \
  -f deploy/edge/compose.coral.yaml \
  up -d
```

Goal:

- acceleration is a measured improvement, not a first-boot dependency

### 7. Lock Down Exposure

Verify from outside the trusted route:

- camera ports are not public
- Frigate is not public
- Scrypted is not public
- Docker did not bind management ports to a public interface

Scrypted uses host networking, so install reviewed host firewall rules before
remote access. The template lives at
`homeops-camera-platform/deploy/edge/firewall/nftables.example.conf`.

Goal:

- remote access goes through the approved private route only

### 8. Register Monitoring And Backups

Add service health and backup ownership to the existing HomeOps observability and
backup conventions.

Initial signals:

- Frigate health
- Scrypted health
- edge heartbeat age
- camera stream up/down
- recording disk usage
- replication queue depth

Goal:

- the edge is visible in the existing operations surface
- config backup ownership is explicit before production use

## Completion Criteria For Phase 1

Phase 1 is ready when:

- one camera is discovered or configured manually
- Frigate records the main stream
- Frigate detects people from the substream
- Scrypted Core live view works over the authorized route
- reboot restores services
- camera and management services are not publicly reachable
- config backup and restore procedure has been tested
