#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home"
export HOME="$TMPDIR/home"
export PATH="$TMPDIR/bin:$PATH"
export WORKQ_DASHBOARD_URL="http://dashboard.test"
export WORKQ_CONDUCTOR_URL="http://conductor.test"
export WORKQ_CONDUCTOR_KEY="test-key"
export CALL_LOG="$TMPDIR/calls.tsv"

cat > "$TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
body=""
url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --data) body="$2"; shift 2 ;;
    -m|-H) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

printf '%s\t%s\t%s\n' "$method" "$url" "$body" >> "$CALL_LOG"
if [[ "$method" == "POST" && "$url" == */projects/10/tasks ]]; then
  printf '{"id":159}\n'
else
  printf '{}\n'
fi
SH
chmod +x "$TMPDIR/bin/curl"

cat > "$TMPDIR/parser-ok" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
test -f "${1:?description file}"
printf '{"target_files":["src/ui.ts"],"reference_files":["src/app.ts"],"targets":[{"action":"modify","path":"src/ui.ts"}]}\n'
SH
chmod +x "$TMPDIR/parser-ok"

cat > "$TMPDIR/parser-bad" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'invalid task\n' >&2
exit 1
SH
chmod +x "$TMPDIR/parser-bad"

cat > "$TMPDIR/task.md" <<'EOF'
CONTEXT
  Test context.

TARGET
- Modify src/ui.ts
- Reference src/app.ts

CHANGE
  Make a small change.

ACCEPTANCE
  npm test exits 0.
EOF

cat > "$TMPDIR/task-two.md" <<'EOF'
# Second queued task

CONTEXT
  Test context.

TARGET
- Modify src/ui.ts
- Reference src/app.ts

CHANGE
  Make a small follow-up change.

ACCEPTANCE
  npm test exits 0.
EOF

export WORKQ_CONTRACT_PARSER="$TMPDIR/parser-bad"
if "$ROOT/scripts/workq.sh" add 10 7 --title "Invalid" --description-file "$TMPDIR/task.md" >/dev/null 2>&1; then
  printf 'expected invalid parser to fail\n' >&2
  exit 1
fi
if [[ -f "$CALL_LOG" ]]; then
  printf 'invalid parser should not call dashboard\n' >&2
  exit 1
fi

export WORKQ_CONTRACT_PARSER="$TMPDIR/parser-ok"
"$ROOT/scripts/workq.sh" add 10 7 --title "Valid" --description-file "$TMPDIR/task.md" --priority 300 --complexity low --label enhancement >/dev/null

python3 - "$CALL_LOG" <<'PY'
import json
import sys

rows = [line.rstrip("\n").split("\t", 2) for line in open(sys.argv[1])]
assert len(rows) == 2, rows
post = json.loads(rows[0][2])
patch = json.loads(rows[1][2])
assert rows[0][0] == "POST", rows
assert rows[1][0] == "PATCH", rows
assert post["selected_repository_id"] == 7, post
assert post["target_entries"] == [{"action": "modify", "path": "src/ui.ts"}], post
assert post["target_files"] == ["src/ui.ts"], post
assert post["reference_files"] == ["src/app.ts"], post
assert patch["selected_repository_id"] == 7, patch
assert patch["target_entries"] == [{"action": "modify", "path": "src/ui.ts"}], patch
assert patch["target_files"] == ["src/ui.ts"], patch
assert patch["reference_files"] == ["src/app.ts"], patch
PY

: > "$CALL_LOG"
"$ROOT/scripts/workq.sh" queue 10 7 "$TMPDIR/task.md" "$TMPDIR/task-two.md" --priority 250 --complexity low >/dev/null

python3 - "$CALL_LOG" <<'PY'
import json
import sys

rows = [line.rstrip("\n").split("\t", 2) for line in open(sys.argv[1])]
assert len(rows) == 4, rows
first = json.loads(rows[0][2])
second = json.loads(rows[2][2])
assert first["title"] == "task", first
assert first["status"] == "open", first
assert first["priority_score"] == 250, first
assert second["title"] == "Second queued task", second
assert second["status"] == "blocked", second
assert second["target_entries"] == [{"action": "modify", "path": "src/ui.ts"}], second
PY
