# Local delivery loop

How to queue work for the local model, run it, and review what comes back.
Written for an agent operating on the owner's behalf. Everything here has been
run against the live system; the failure modes listed are ones that actually
happened, not ones imagined.

Contents: what the system does, writing a task, pre-flighting it, queueing,
running, reviewing, and what to do when it fails.

## What actually runs

`POST /runs` on the conductor starts the **workflow engine**: a sixty-step
pipeline per task that scans the repository, plans, implements, runs the
repository's own tests, and merges to `main` when its reviews pass. It branches
from the task's milestone slug, so several tasks on one milestone accumulate on
one branch.

Two things bound it:

- **Fail-fast is on inside a project.** The first task that fails ends that
  project's run. This is deliberate: an unrecoverable failure should not drag
  the rest of the queue through the same wall. Do not turn it off.
- **A run takes a list of projects.** When one project finishes — pass or fail —
  the run moves to the next. The run only fails if every project failed.

Planning is deterministic. The planner persona does not run; the task is
expected to arrive with its files already identified. This is a deliberate
decision from 2026-07-12: planning effort goes in up front, in a
better-specified task. Write tasks accordingly.

## Writing a task

The task description **is** the specification. The model gets the repository
file listing and the description; it does not explore.

### The planner reads file paths out of your prose

Every path-shaped string in the title or description becomes a plan step. The
pattern is a path rooted at `src`, `tests`, `test`, `app`, `components`, `lib`,
`packages`, `scripts`, `public`, `config` or `__tests__`, ending in a known
extension.

This means a path mentioned as *background* becomes a file the model is told to
rewrite. A task that said "read `src/roles.ts` for the permission names" got a
plan step to reimplement `src/roles.ts`.

**Mention only the files you want changed.** Refer to everything else by name:
"the roles module, in the repository listing". Check before queueing:

```bash
grep -oE '(src|tests|test|app|components|lib|packages|scripts|public|config|__tests__)/[A-Za-z0-9_./@+-]+\.(ts|tsx|js|jsx|json|md)' spec.txt | sort -u
```

### Required sections

Facts first, then what to change, then an output-format block. The output-format
block is not optional — without it the model has produced a corrupted path
(`analytics.test.ts__`) and rewritten the file it was told to leave alone.

```
Reply with exactly one block, opened with the line

    ```file path=<the exact target path>

and closed with a bare triple-backtick line. Write no prose before or after that
block. Copy that path character for character — do not add a suffix, change the
extension, or alter the directory.

Do not open the block with ```ts or ```typescript — those are ignored and the
task fails. Emit no block for any other path: this task changes exactly one
file, and a block for <the file to protect> will be rejected.
```

### Carry the repository's conventions

The model does not know them and will not infer them. Every one of these has
cost a run:

| Convention | What to write |
| --- | --- |
| Test globals | `soccer-coaching-hub` and `mermaid-quest-academy` need `import { describe, expect, it } from 'vitest'` or the file fails to load with "describe is not defined". `dnd-campaign-table` and `public-future-initiative` run jest with globals — importing them breaks convention. |
| Mocks | Say "do not use `vi`, `vi.fn()`, `jest.fn()`" **and why**: a mocked repository cannot exercise the lookup the rule depends on. Without the reason the model mocks anyway. |
| Spy API | It has written `jest.spy`, which does not exist. Say `jest.spyOn`. |
| Spy hygiene | It does not restore spies, so a later test sees earlier calls. Ask for `afterEach(() => jest.restoreAllMocks())`. |
| `process.env` | Assigning `process.env.NODE_ENV` fails typecheck. Ask for a cast and a restore in a `finally`. |
| Type helpers | A helper returning `{ called, fn }` was typed `{ called: boolean }`, so the file would not compile and **no test in the project ran**. Ask that every returned property be declared. |
| eslint | `soccer-coaching-hub` forbids `!=` and `==`, caps method complexity at 10, and warns on magic numbers. |
| Extending a guard | Say "extend the existing guard", not "add a check before X" — the latter produced a second parallel block and pushed a method over the complexity limit. |

### Size

Keep to roughly six test cases per task. An eight-case spec produced no output
at all on one of three probes: the model ran out of output tokens mid-file.

### Shape that works

Test-only tasks against code that is already correct have the best record. The
model's implementations have been right first time; test authoring is where it
stumbles. Put the weight there.

## Pre-flight

**Probe the real model three times before queueing.** This costs a few minutes
and has caught a bad spec every time it mattered.

```bash
./scripts/local-delivery/build-inventory.sh /path/to/repo > inventory.txt
python3 ./scripts/local-delivery/probe-spec.py "$LMS_BASE_URL" spec.txt inventory.txt
```

Both helpers live in `scripts/local-delivery/`. The probe sends the same system
prompt and the same repository listing the workflow will send, so what it emits
is what the run will get.

Accept only **three for three**, each emitting exactly one block at exactly the
target path. Two of three is not good enough — fix the spec.

## Queueing

Every task needs three things beyond its description:

- `milestone_id` — without it the task credits no roadmap and appears in no
  milestone review. This was missed for 165 tasks.
- `selected_repository_id`
- `delegation_status` — `local_ready` for work the local model should take.
  Mark anything it should not attempt `premium_ready`, `human_required` or
  `unsupported` and it will be left in the backlog untouched.

```bash
curl -s -X POST "$WORKQ_DASHBOARD_URL/projects/<pid>/tasks" \
  -H 'Content-Type: application/json' \
  -d '{"title":"...","description":"...","status":"open",
       "priority_score":900,"execution_complexity":"medium",
       "selected_repository_id":<rid>,"milestone_id":<mid>,
       "delegation_status":"local_ready"}'
```

Do not invent tasks to pad a batch. A fabricated probe task was queued against a
real milestone and left that milestone permanently unable to reach 100%.

## Running

```bash
curl -s -X POST "$WORKQ_CONDUCTOR_URL/runs" \
  -H "Authorization: Bearer $WORKQ_CONDUCTOR_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"project_ids": [17, 20, 18]}'
```

One task takes roughly ten to fifteen minutes. Poll `/runs/<id>` until the
status is terminal; read `/runs/<id>/logs?tail=400` for detail. Each project's
log lines carry its own `projectId`.

The conductor is single-flight. A second run while one is in progress returns
409.

## Reviewing

**A task reported `done` has already merged to `main`.** Reviewing is checking
what landed, not approving it.

For each task, find the milestone branch or the merge on `main`:

```bash
git fetch forgejo && git log --oneline forgejo/main -3
git diff --stat forgejo/main~1 forgejo/main
```

Then, in a throwaway worktree:

1. Run the repository's full gate — not just the new file. A type error in one
   test file stops every test in the project from running, and the count still
   reads green if you only look at the new file.
2. **Sabotage the code under test.** Break the specific rule the test claims to
   guard, re-run, and confirm the test fails. Restore and confirm green. A test
   that has never been seen to fail proves nothing — generated tests have
   passed while mocking away the very thing they claimed to cover.
3. A surviving mutation is not always a coverage gap. One survived because the
   code it targeted was unreachable; the right answer was to say so, not to
   manufacture a test.

Then close the task and check the milestone moved:

```bash
curl -s -X PATCH "$WORKQ_DASHBOARD_URL/projects/<pid>/tasks/<tid>" \
  -H 'Content-Type: application/json' -d '{"status":"done"}'
```

## When it fails

The task goes to `blocked` and the branch keeps whatever was committed. Read the
error before assuming the model is at fault — most failures so far were the
environment, not the output.

| Symptom | Cause |
| --- | --- |
| `<binary>: not found` | A dev dependency is missing. The container sets `NODE_ENV=production`; installs must pass `--include=dev`. |
| `This is not the tsc command you are looking for` | `npx tsc` fetched an unrelated registry package because no local compiler was installed. |
| Peer dependency conflict on install | A lockfile was discarded. `npm ci` against the committed lockfile resolves what `npm install --no-package-lock` cannot. |
| `Unbalanced braces: N open vs M close` | The model's output was truncated. Shrink the spec. |
| `non-target file was modified` | The spec mentioned a path it should not have, or lacked the output-format block. |
| Model rewrites `package.json` on a docs task | An environmental gate failure fed back as a repair prompt. Fix the environment, not the spec. |

A blocked task is evidence. Read it before reopening it.

## Do not

- Do not disable fail-fast to push a batch through.
- Do not widen a gate to make something pass.
- Do not merge a branch whose gate you have not run yourself.
- Do not queue work while the owner is present unless asked; batches belong to
  windows when they are away.
