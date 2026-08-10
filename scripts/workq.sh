#!/usr/bin/env bash
# workq — deterministic queue/track interface for the local execution
# workflow (project-dashboard + task-flow-conductor). Designed so agents and
# automation can operate the full task lifecycle without LLM involvement.
#
# Configuration (environment, e.g. sourced from a private env file):
#   WORKQ_DASHBOARD_URL   – project-dashboard base URL
#   WORKQ_CONDUCTOR_URL   – task-flow-conductor base URL
#   WORKQ_CONDUCTOR_KEY   – conductor bearer key (only for resume/pause/status)
#
# Commands:
#   workq add <projectId> <repoId> --title <t> --description-file <f>
#             [--priority <n>] [--complexity low|medium|high] [--label <l>]...
#   workq board                      – portfolio across all states
#   workq list <state>               – queued|running|blocked|awaiting_review|recently_completed
#   workq attempts <taskId>          – attempt history for a task
#   workq review <projectId> <taskId> <outcome> [notes]
#             – record review outcome on the latest succeeded attempt and mark the task done
#             – outcomes: accepted_as_is accepted_with_minor_edits accepted_with_major_edits rejected
#   workq reopen <projectId> <taskId>  – requeue a task (status open, claim cleared)
#   workq drop <projectId> <taskId>    – mark a task cancelled without running it
#   workq resume | pause | status      – conductor dispatch control
#
# shellcheck shell=bash
set -euo pipefail

die() { printf 'workq: %s\n' "$*" >&2; exit 1; }
require() { [[ -n "${!1:-}" ]] || die "$1 is not set"; }

json() { python3 -c "$1" "${@:2}"; }

dash() {
  require WORKQ_DASHBOARD_URL
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -m 30 -X "$method" -H 'Content-Type: application/json')
  [[ -n "$body" ]] && args+=(--data "$body")
  curl "${args[@]}" "${WORKQ_DASHBOARD_URL%/}${path}"
}

cond() {
  require WORKQ_CONDUCTOR_URL; require WORKQ_CONDUCTOR_KEY
  local method="$1" path="$2"
  curl -sS -m 30 -X "$method" -H "Authorization: Bearer ${WORKQ_CONDUCTOR_KEY}" "${WORKQ_CONDUCTOR_URL%/}${path}"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  add)
    project="${1:?projectId}"; repo="${2:?repoId}"; shift 2
    title="" descfile="" priority=100 complexity="low"; labels=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) title="$2"; shift 2 ;;
        --description-file) descfile="$2"; shift 2 ;;
        --priority) priority="$2"; shift 2 ;;
        --complexity) complexity="$2"; shift 2 ;;
        --label) labels+=("$2"); shift 2 ;;
        *) die "unknown flag: $1" ;;
      esac
    done
    [[ -n "$title" && -n "$descfile" ]] || die "--title and --description-file are required"
    [[ -f "$descfile" ]] || die "description file not found: $descfile"
    grep -q 'CONTEXT' "$descfile" && grep -q 'TARGET' "$descfile" \
      && grep -q 'CHANGE' "$descfile" && grep -q 'ACCEPTANCE' "$descfile" \
      || die "description must contain CONTEXT/TARGET/CHANGE/ACCEPTANCE (see directed-task-contract.md)"
    body="$(python3 - "$title" "$descfile" "$priority" "$complexity" "${labels[@]:-}" <<'PYEOF'
import json, sys
title, descfile, priority, complexity, *labels = sys.argv[1:]
print(json.dumps({
    "title": title,
    "description": open(descfile).read(),
    "status": "open",
    "priority_score": int(priority),
    "execution_complexity": complexity,
    "labels": [l for l in labels if l],
}))
PYEOF
)"
    created="$(dash POST "/projects/${project}/tasks" "$body")"
    task_id="$(printf '%s' "$created" | json 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
    [[ -n "$task_id" ]] || die "task creation failed: $created"
    dash PATCH "/projects/${project}/tasks/${task_id}" "{\"selected_repository_id\": ${repo}}" >/dev/null
    printf 'queued task %s (project %s, repo %s, priority %s)\n' "$task_id" "$project" "$repo" "$priority"
    ;;
  board)
    for state in running queued awaiting_review blocked recently_completed; do
      printf '== %s ==\n' "$state"
      dash GET "/portfolio?state=${state}" | json '
import json,sys
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get("tasks") or d.get("data") or d.get("items") or []
for t in items:
    print(" ", t.get("task_id") or t.get("id"), "|", "p"+str(t.get("project_id")), "|", (t.get("title") or "")[:64], "|", t.get("attempt_status") or t.get("status") or "")
if not items: print("  (none)")'
    done
    ;;
  list)
    state="${1:?state}"
    dash GET "/portfolio?state=${state}"
    echo
    ;;
  attempts)
    task="${1:?taskId}"
    dash GET "/execution/attempts?task_id=${task}" | json '
import json,sys
for a in json.load(sys.stdin)["data"]:
    print({k:a.get(k) for k in ("id","attempt_number","status","backend","failure_category","pr_url","review_outcome")})'
    ;;
  review)
    project="${1:?projectId}"; task="${2:?taskId}"; outcome="${3:?outcome}"; notes="${4:-}"
    attempt="$(dash GET "/execution/attempts?task_id=${task}" | json '
import json,sys
d=[a for a in json.load(sys.stdin)["data"] if a["status"]=="succeeded" and a.get("pr_url")]
print(d[0]["id"] if d else "")')"
    [[ -n "$attempt" ]] || die "no succeeded attempt with a PR found for task ${task}"
    body="$(python3 - "$outcome" "$notes" <<'PYEOF'
import json, sys
outcome, notes = sys.argv[1], sys.argv[2]
payload = {"review_outcome": outcome}
if notes: payload["review_notes"] = notes
print(json.dumps(payload))
PYEOF
)"
    dash PATCH "/execution/attempts/${attempt}" "$body" >/dev/null
    dash PATCH "/projects/${project}/tasks/${task}" '{"status":"done"}' >/dev/null
    printf 'task %s done; attempt %s outcome=%s\n' "$task" "$attempt" "$outcome"
    ;;
  reopen)
    project="${1:?projectId}"; task="${2:?taskId}"
    dash PATCH "/projects/${project}/tasks/${task}" '{"status":"open","claimed_by":null}' >/dev/null
    printf 'task %s reopened\n' "$task"
    ;;
  drop)
    project="${1:?projectId}"; task="${2:?taskId}"
    dash PATCH "/projects/${project}/tasks/${task}" '{"status":"cancelled"}' >/dev/null
    printf 'task %s cancelled\n' "$task"
    ;;
  resume) cond POST /execution/resume; echo ;;
  pause) cond POST /execution/pause; echo ;;
  status) cond GET /execution/status; echo ;;
  *)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
