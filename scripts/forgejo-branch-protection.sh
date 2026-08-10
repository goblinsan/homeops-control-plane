#!/usr/bin/env bash
# scripts/forgejo-branch-protection.sh
#
# Apply or verify the autonomous-workforce enforcement contract on a Forgejo
# repository (docs/autonomous-workforce/plan-v2.md, "Enforcement Model"):
#
#   - the default branch has a protection rule
#   - direct pushes are restricted to an explicit allowlist of humans
#   - merges are restricted to the same allowlist, plus any --merge-user
#     machine identities (repositories with merge_policy=auto_on_validation)
#   - the bot identity is NOT in either allowlist
#   - a merge-user identity is NOT in the push allowlist
#   - the bot and merge-user identities are plain "write" collaborators
#
# The policy tables in project-dashboard are routing hints; this server-side
# configuration is the invariant. Verify mode is what the conductor's
# pre-write protection check will call in Phase 3A.
#
# Required environment variables:
#   FORGEJO_BASE_URL     - Base URL of the Forgejo instance
#                          e.g. http://forgejo.example.internal:3000
#   FORGEJO_TOKEN        - Token with repo admin rights on the target repo
#
# Usage:
#   ./scripts/forgejo-branch-protection.sh \
#     --owner homeops --repo project-dashboard --branch main \
#     --allow-user <operator-username> --bot conductor-bot \
#     --verify            # or --apply
#
# --apply is idempotent: it creates or updates the protection rule and, when
# --bot is given, ensures the bot is a write collaborator.
#
# shellcheck shell=bash

set -euo pipefail

FORGEJO_BASE_URL="${FORGEJO_BASE_URL:-}"
FORGEJO_TOKEN="${FORGEJO_TOKEN:-}"

OWNER=""
REPO=""
BRANCH="main"
BOT_USER=""
MODE=""
ALLOW_USERS=()
MERGE_USERS=()

log() { printf '[forgejo-branch-protection] %s\n' "$*"; }
err() { printf '[forgejo-branch-protection] ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  forgejo-branch-protection.sh --owner <owner> --repo <repo> (--verify | --apply)
                               [--branch <name>] [--allow-user <name>]...
                               [--bot <name>]

Options:
  --owner <name>        Repository owner or org
  --repo <name>         Repository name
  --branch <name>       Protected branch (default: main)
  --allow-user <name>   Human allowed to push/merge the protected branch
                        (repeatable; required for --apply)
  --merge-user <name>   Machine identity allowed to MERGE but never push
                        (repeatable; for merge_policy=auto_on_validation)
  --bot <name>          Bot identity that must be excluded from the
                        allowlists and hold plain write permission
  --verify              Check the contract; exit non-zero on any violation
  --apply               Create/update the protection rule (idempotent)
  --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) [[ $# -ge 2 ]] || die "--owner requires a value"; OWNER="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --branch) [[ $# -ge 2 ]] || die "--branch requires a value"; BRANCH="$2"; shift 2 ;;
    --allow-user) [[ $# -ge 2 ]] || die "--allow-user requires a value"; ALLOW_USERS+=("$2"); shift 2 ;;
    --merge-user) [[ $# -ge 2 ]] || die "--merge-user requires a value"; MERGE_USERS+=("$2"); shift 2 ;;
    --bot) [[ $# -ge 2 ]] || die "--bot requires a value"; BOT_USER="$2"; shift 2 ;;
    --verify) MODE="verify"; shift ;;
    --apply) MODE="apply"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$FORGEJO_BASE_URL" ]] || die "FORGEJO_BASE_URL is not set"
[[ -n "$FORGEJO_TOKEN" ]] || die "FORGEJO_TOKEN is not set"
[[ -n "$OWNER" ]] || die "--owner is required"
[[ -n "$REPO" ]] || die "--repo is required"
[[ -n "$MODE" ]] || die "Exactly one of --verify or --apply is required"

if [[ "$MODE" == "apply" && ${#ALLOW_USERS[@]} -eq 0 ]]; then
  die "--apply requires at least one --allow-user (otherwise nobody can push or merge ${BRANCH})"
fi
if [[ -n "$BOT_USER" ]]; then
  for u in "${ALLOW_USERS[@]:-}"; do
    [[ "$u" == "$BOT_USER" ]] && die "--bot ${BOT_USER} must not also be an --allow-user"
  done
  for u in "${MERGE_USERS[@]:-}"; do
    [[ "$u" == "$BOT_USER" ]] && die "--bot ${BOT_USER} must not also be a --merge-user"
  done
fi

require_cmd curl
require_cmd jq

API="${FORGEJO_BASE_URL%/}/api/v1"
AUTH=(-H "Authorization: token ${FORGEJO_TOKEN}")
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

api() {
  local method="$1" path="$2" body="${3:-}"
  local response="$WORK_DIR/response.json"
  local args=(-sS -o "$response" -w '%{http_code}' -X "$method" "${AUTH[@]}" -H 'Content-Type: application/json')
  [[ -n "$body" ]] && args+=(--data "$body")
  HTTP_CODE="$(curl "${args[@]}" "${API}${path}")"
  RESPONSE_FILE="$response"
}

allowlist_json() {
  printf '%s\n' "${ALLOW_USERS[@]}" | jq -R . | jq -s .
}

merge_allowlist_json() {
  printf '%s\n' "${ALLOW_USERS[@]}" "${MERGE_USERS[@]:-}" | jq -R . | jq -s '[.[] | select(length > 0)]'
}

find_rule() {
  api GET "/repos/${OWNER}/${REPO}/branch_protections"
  [[ "$HTTP_CODE" == "200" ]] || die "Listing branch protections failed (HTTP ${HTTP_CODE})"
  jq --arg branch "$BRANCH" \
    '[.[] | select((.rule_name // .branch_name) == $branch)] | first // empty' \
    "$RESPONSE_FILE" > "$WORK_DIR/rule.json"
  [[ -s "$WORK_DIR/rule.json" ]]
}

apply_protection() {
  local payload
  payload="$(jq -n \
    --arg branch "$BRANCH" \
    --argjson allow "$(allowlist_json)" \
    --argjson merge_allow "$(merge_allowlist_json)" \
    '{
      rule_name: $branch,
      branch_name: $branch,
      enable_push: true,
      enable_push_whitelist: true,
      push_whitelist_usernames: $allow,
      enable_merge_whitelist: true,
      merge_whitelist_usernames: $merge_allow
    }')"

  if find_rule; then
    api PATCH "/repos/${OWNER}/${REPO}/branch_protections/${BRANCH}" "$payload"
    [[ "$HTTP_CODE" == "200" ]] || die "Updating protection failed (HTTP ${HTTP_CODE}): $(cat "$RESPONSE_FILE")"
    log "Updated protection rule for ${OWNER}/${REPO}@${BRANCH}"
  else
    api POST "/repos/${OWNER}/${REPO}/branch_protections" "$payload"
    [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]] || die "Creating protection failed (HTTP ${HTTP_CODE}): $(cat "$RESPONSE_FILE")"
    log "Created protection rule for ${OWNER}/${REPO}@${BRANCH}"
  fi

  if [[ -n "$BOT_USER" ]]; then
    api PUT "/repos/${OWNER}/${REPO}/collaborators/${BOT_USER}" '{"permission":"write"}'
    [[ "$HTTP_CODE" == "204" || "$HTTP_CODE" == "200" ]] || die "Adding ${BOT_USER} as write collaborator failed (HTTP ${HTTP_CODE})"
    log "Ensured ${BOT_USER} is a write collaborator"
  fi

  for mu in "${MERGE_USERS[@]:-}"; do
    [[ -n "$mu" ]] || continue
    api PUT "/repos/${OWNER}/${REPO}/collaborators/${mu}" '{"permission":"write"}'
    [[ "$HTTP_CODE" == "204" || "$HTTP_CODE" == "200" ]] || die "Adding ${mu} as write collaborator failed (HTTP ${HTTP_CODE})"
    log "Ensured merge user ${mu} is a write collaborator"
  done
}

verify_protection() {
  local failures=0

  if ! find_rule; then
    err "No protection rule exists for ${OWNER}/${REPO}@${BRANCH}"
    exit 1
  fi

  local push_ok
  push_ok="$(jq --arg bot "$BOT_USER" '
    if .enable_push == false then true
    elif (.enable_push_whitelist == true) then
      (if $bot == "" then true
       else ((.push_whitelist_usernames // []) | index($bot) | not) end)
    else false end' "$WORK_DIR/rule.json")"
  if [[ "$push_ok" != "true" ]]; then
    err "Push to ${BRANCH} is not restricted, or the bot is in the push allowlist"
    failures=$((failures + 1))
  fi

  local merge_ok
  merge_ok="$(jq --arg bot "$BOT_USER" '
    if (.enable_merge_whitelist == true) then
      (if $bot == "" then true
       else ((.merge_whitelist_usernames // []) | index($bot) | not) end)
    else false end' "$WORK_DIR/rule.json")"
  if [[ "$merge_ok" != "true" ]]; then
    err "Merging into ${BRANCH} is not allowlisted, or the bot is in the merge allowlist"
    failures=$((failures + 1))
  fi

  for mu in "${MERGE_USERS[@]:-}"; do
    [[ -n "$mu" ]] || continue
    local merge_user_push_ok
    merge_user_push_ok="$(jq --arg mu "$mu" '
      if .enable_push == false then true
      elif (.enable_push_whitelist == true) then
        ((.push_whitelist_usernames // []) | index($mu) | not)
      else false end' "$WORK_DIR/rule.json")"
    if [[ "$merge_user_push_ok" != "true" ]]; then
      err "Merge user ${mu} must not be in the push allowlist for ${BRANCH}"
      failures=$((failures + 1))
    fi
  done

  if [[ -n "$BOT_USER" ]]; then
    api GET "/repos/${OWNER}/${REPO}/collaborators/${BOT_USER}/permission"
    if [[ "$HTTP_CODE" != "200" ]]; then
      err "Could not read ${BOT_USER} permission (HTTP ${HTTP_CODE}); is the bot a collaborator?"
      failures=$((failures + 1))
    else
      local perm
      perm="$(jq -r '.permission // empty' "$RESPONSE_FILE")"
      if [[ "$perm" != "write" ]]; then
        err "Bot ${BOT_USER} permission is '${perm:-none}', expected exactly 'write'"
        failures=$((failures + 1))
      fi
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    die "Verification failed with ${failures} violation(s) for ${OWNER}/${REPO}@${BRANCH}"
  fi
  log "OK: ${OWNER}/${REPO}@${BRANCH} satisfies the enforcement contract"
}

case "$MODE" in
  apply) apply_protection; verify_protection ;;
  verify) verify_protection ;;
esac
