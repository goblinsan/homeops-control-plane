#!/usr/bin/env bash
# scripts/audit-forgejo-deploy-hooks.sh
#
# Deploy-hook audit for the autonomous-workforce enforcement model
# (docs/autonomous-workforce/plan-v2.md): before a repository with deploy
# automation becomes write-enabled, confirm its post-receive automation only
# fires for the default branch ref. A hook keyed on any ref would deploy a
# bot work branch.
#
# The script fetches server-side git hooks and webhooks, applies a
# conservative heuristic, and prints the full hook content for human review.
# A PASS heuristic is advisory; the audit is complete only when a human has
# read the content. Anything the heuristic cannot prove safe is REVIEW.
#
# Required environment variables:
#   FORGEJO_BASE_URL     - Base URL of the Forgejo instance
#                          e.g. http://forgejo.example.internal:3000
#   FORGEJO_TOKEN        - Token with admin rights (git hooks need admin)
#
# Usage:
#   ./scripts/audit-forgejo-deploy-hooks.sh --owner homeops --repo project-dashboard
#
# Exit codes: 0 = nothing needs review, 2 = at least one hook needs review.
#
# shellcheck shell=bash

set -euo pipefail

FORGEJO_BASE_URL="${FORGEJO_BASE_URL:-}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"

OWNER=""
REPO=""
BRANCH="main"

log() { printf '[audit-deploy-hooks] %s\n' "$*"; }
err() { printf '[audit-deploy-hooks] ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  audit-forgejo-deploy-hooks.sh --owner <owner> --repo <repo> [--branch <name>]

Options:
  --owner <name>     Repository owner or org
  --repo <name>      Repository name
  --branch <name>    Default branch deploys are expected on (default: main)
  --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) [[ $# -ge 2 ]] || die "--owner requires a value"; OWNER="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --branch) [[ $# -ge 2 ]] || die "--branch requires a value"; BRANCH="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$FORGEJO_BASE_URL" ]] || die "FORGEJO_BASE_URL is not set"
[[ -n "$FORGEJO_TOKEN" ]] || die "FORGEJO_TOKEN is not set"
[[ -n "$OWNER" ]] || die "--owner is required"
[[ -n "$REPO" ]] || die "--repo is required"

command -v curl >/dev/null 2>&1 || die "Required command not found: curl"
command -v jq >/dev/null 2>&1 || die "Required command not found: jq"

API="${FORGEJO_BASE_URL%/}/api/v1"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fetch() {
  local path="$1" out="$2"
  local code
  code="$(curl -sS -o "$out" -w '%{http_code}' \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    "${API}${path}")"
  printf '%s' "$code"
}

NEEDS_REVIEW=0

log "Auditing ${OWNER}/${REPO} (default branch: ${BRANCH})"

# Server-side git hooks (post-receive et al.) are where push-triggered deploy
# automation lives; reading them requires an admin token.
GIT_HOOKS="$WORK_DIR/git-hooks.json"
CODE="$(fetch "/repos/${OWNER}/${REPO}/hooks/git" "$GIT_HOOKS")"
if [[ "$CODE" != "200" ]]; then
  err "Could not list git hooks (HTTP ${CODE}); an admin token is required. Audit incomplete."
  exit 2
fi

ACTIVE_COUNT="$(jq '[.[] | select(.is_active == true)] | length' "$GIT_HOOKS")"
if [[ "$ACTIVE_COUNT" == "0" ]]; then
  log "No active server-side git hooks."
else
  while IFS= read -r name; do
    CONTENT="$(jq -r --arg n "$name" '.[] | select(.name == $n) | .content // ""' "$GIT_HOOKS")"
    printf '\n===== git hook: %s =====\n%s\n===== end hook =====\n\n' "$name" "$CONTENT"
    if printf '%s' "$CONTENT" | grep -Eq "refs/heads/${BRANCH}([^A-Za-z0-9_-]|\$)"; then
      log "HEURISTIC PASS: hook '${name}' references refs/heads/${BRANCH} — confirm by reading it above that non-${BRANCH} refs are ignored."
    else
      err "REVIEW: hook '${name}' has no visible refs/heads/${BRANCH} filter — a push to ANY ref may trigger it."
      NEEDS_REVIEW=$((NEEDS_REVIEW + 1))
    fi
  done < <(jq -r '.[] | select(.is_active == true) | .name' "$GIT_HOOKS")
fi

# Webhooks that fire on push can also drive deployments; report their
# branch filters for the same human review.
WEBHOOKS="$WORK_DIR/webhooks.json"
CODE="$(fetch "/repos/${OWNER}/${REPO}/hooks" "$WEBHOOKS")"
if [[ "$CODE" != "200" ]]; then
  err "Could not list webhooks (HTTP ${CODE}). Audit incomplete."
  exit 2
fi

PUSH_HOOKS="$(jq '[.[] | select(.active == true) | select((.events // []) | index("push"))] | length' "$WEBHOOKS")"
if [[ "$PUSH_HOOKS" == "0" ]]; then
  log "No active push-event webhooks."
else
  while IFS= read -r row; do
    id="$(jq -r '.id' <<<"$row")"
    filter="$(jq -r '.branch_filter // "*"' <<<"$row")"
    if [[ "$filter" == "$BRANCH" ]]; then
      log "HEURISTIC PASS: webhook ${id} filters on branch '${filter}'."
    else
      err "REVIEW: webhook ${id} has branch filter '${filter}' — it fires for more than '${BRANCH}'."
      NEEDS_REVIEW=$((NEEDS_REVIEW + 1))
    fi
  done < <(jq -c '.[] | select(.active == true) | select((.events // []) | index("push"))' "$WEBHOOKS")
fi

if [[ "$NEEDS_REVIEW" -gt 0 ]]; then
  err "${NEEDS_REVIEW} item(s) need review before this repository may be write-enabled."
  exit 2
fi
log "Audit heuristics passed. Complete the audit by reading the hook content printed above."
