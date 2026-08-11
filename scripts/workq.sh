#!/bin/bash
# workq — deterministic queue/track interface for the local execution
# workflow (project-dashboard + task-flow-conductor). Designed so agents and
# automation can operate the full task lifecycle without LLM involvement.
#
# Configuration (environment, e.g. sourced from a private env file):
#   WORKQ_DASHBOARD_URL   – project-dashboard base URL
#   WORKQ_CONDUCTOR_URL   – task-flow-conductor base URL
#   WORKQ_CONDUCTOR_KEY   – conductor bearer key (only for resume/pause/status)
#   WORKQ_CONTRACT_PARSER – executable directed-task parser path
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
#   workq drop <projectId> <taskId>    – archive a task without running it
#   workq resume | pause | status      – conductor dispatch control
#
# shellcheck shell=bash
set -euo pipefail

if [[ -z "${WORKQ_DASHBOARD_URL:-}" || -z "${WORKQ_CONDUCTOR_URL:-}" || -z "${WORKQ_CONDUCTOR_KEY:-}" ]]; then
  if [[ -f "${HOME}/.homeops/workq.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${HOME}/.homeops/workq.env"
    set +a
  fi
fi

die() { printf 'workq: %s\n' "$*" >&2; exit 1; }
require() { [[ -n "${!1:-}" ]] || die "$1 is not set"; }

json() { node -e "$1" "${@:2}"; }

dash() {
  require WORKQ_DASHBOARD_URL
  local method="$1" path="$2" body="${3:-}"
  local args=(-fsS -m 30 -X "$method" -H 'Content-Type: application/json')
  [[ -n "$body" ]] && args+=(--data "$body")
  curl "${args[@]}" "${WORKQ_DASHBOARD_URL%/}${path}"
}

cond() {
  require WORKQ_CONDUCTOR_URL; require WORKQ_CONDUCTOR_KEY
  local method="$1" path="$2"
  curl -fsS -m 30 -X "$method" -H "Authorization: Bearer ${WORKQ_CONDUCTOR_KEY}" "${WORKQ_CONDUCTOR_URL%/}${path}"
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
    require WORKQ_CONTRACT_PARSER
    [[ -x "$WORKQ_CONTRACT_PARSER" ]] || die "WORKQ_CONTRACT_PARSER is not executable: $WORKQ_CONTRACT_PARSER"
    parsed="$("$WORKQ_CONTRACT_PARSER" "$descfile")" || die "description failed directed-task contract parsing"
    body="$(node -e 'const fs = require("fs");
const [title, descfile, priority, complexity, repo, parsedJson, ...labels] = process.argv.slice(1);
const parsed = JSON.parse(parsedJson);
console.log(JSON.stringify({
  title,
  description: fs.readFileSync(descfile, "utf8"),
  status: "open",
  priority_score: Number(priority),
  execution_complexity: complexity,
  selected_repository_id: Number(repo),
  target_entries: parsed.targets,
  target_files: parsed.target_files,
  reference_files: parsed.reference_files,
  labels: labels.filter(Boolean),
}));' "$title" "$descfile" "$priority" "$complexity" "$repo" "$parsed" "${labels[@]:-}")"
    created="$(dash POST "/projects/${project}/tasks" "$body")"
    task_id="$(printf '%s' "$created" | json 'const fs = require("fs"); const body = JSON.parse(fs.readFileSync(0, "utf8")); console.log(body.id || "");')"
    [[ -n "$task_id" ]] || die "task creation failed: $created"
    patch_body="$(node -e 'const [repo, parsedJson] = process.argv.slice(1);
const parsed = JSON.parse(parsedJson);
console.log(JSON.stringify({
  selected_repository_id: Number(repo),
  target_entries: parsed.targets,
  target_files: parsed.target_files,
  reference_files: parsed.reference_files,
}));' "$repo" "$parsed")"
    dash PATCH "/projects/${project}/tasks/${task_id}" "$patch_body" >/dev/null
    printf 'queued task %s (project %s, repo %s, priority %s)\n' "$task_id" "$project" "$repo" "$priority"
    ;;
  board)
    for state in running queued awaiting_review blocked recently_completed; do
      printf '== %s ==\n' "$state"
      dash GET "/portfolio?state=${state}" | json '
const fs = require("fs");
const d = JSON.parse(fs.readFileSync(0, "utf8"));
const items = Array.isArray(d) ? d : (d.tasks || d.data || d.items || []);
for (const t of items) {
  console.log(" ", t.task_id || t.id, "|", "p" + String(t.project_id), "|", String(t.title || "").slice(0, 64), "|", t.attempt_status || t.status || "");
}
if (!items.length) console.log("  (none)");'
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
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(0, "utf8"));
for (const a of body.data) {
  console.log(JSON.stringify({
    id: a.id,
    attempt_number: a.attempt_number,
    status: a.status,
    backend: a.backend,
    failure_category: a.failure_category,
    pr_url: a.pr_url,
    review_outcome: a.review_outcome,
  }));
}'
    ;;
  review)
    project="${1:?projectId}"; task="${2:?taskId}"; outcome="${3:?outcome}"; notes="${4:-}"
    attempt="$(dash GET "/execution/attempts?task_id=${task}" | json '
const fs = require("fs");
const body = JSON.parse(fs.readFileSync(0, "utf8"));
const attempts = body.data.filter((a) => a.status === "succeeded" && a.pr_url);
console.log(attempts.length ? attempts[0].id : "");')"
    [[ -n "$attempt" ]] || die "no succeeded attempt with a PR found for task ${task}"
    body="$(node -e 'const [outcome, notes] = process.argv.slice(1);
const payload = { review_outcome: outcome };
if (notes) payload.review_notes = notes;
console.log(JSON.stringify(payload));' "$outcome" "$notes")"
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
    dash PATCH "/projects/${project}/tasks/${task}" '{"status":"archived"}' >/dev/null
    printf 'task %s archived\n' "$task"
    ;;
  resume) cond POST /execution/resume; echo ;;
  pause) cond POST /execution/pause; echo ;;
  status) cond GET /execution/status; echo ;;
  *)
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
