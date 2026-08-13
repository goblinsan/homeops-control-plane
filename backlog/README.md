# Local execution backlog

Vetted directed-task contracts, ready to be queued at any time by any agent or by the
operator. Nothing here is running. Queueing is a deliberate act.

Every file in this directory has already cleared both intake gates:

- the directed-task contract parser (`WORKQ_CONTRACT_PARSER`), and
- `POST /plans/evaluate`, returning `fits` / `local-14b` / `risk: low`.

A contract that fails either gate does not belong here. Re-check before queueing if the
target repository has changed since the contract was written.

## How an agent picks work up

The full procedure is in `runbooks/local-workflow-queue.md` section 8. The short version:

```bash
workq.sh board                                   # what is already running
workq.sh queue 14 8 backlog/roblox-components/01-docs-testing.md \
        --priority 840 --complexity low --label unattended-batch
workq.sh board                                   # confirm it was picked up
```

Queue one file per invocation unless the contracts touch different files and none of them
depends on another's output. `workq queue` with several files opens only the first and
holds the rest `blocked`, which is the right default for a chain.

## Inventory

### roblox-components (project 14, repository 8)

Repository posture: `auto_on_validation`, dispatch `background_ok`. The gate is seven
commands covering Luau in `components/` and `tools/`, Markdown in `docs/`, the catalog
generator's behaviour, and 367 component specs. What that gate does and does not prove is
written down in that repository at `docs/auto-merge-safety-boundary.md`.

| File | Creates | Unattended | Depends on |
| --- | --- | --- | --- |
| `01-docs-testing.md` | `docs/testing.md` | yes | — |
| `02-docs-harness.md` | `docs/harness.md` | yes | — |
| `03-docs-composition.md` | `docs/composition.md` | yes | `docs/catalog-index.md` (already on main) |

All three create a new file that nothing else in the backlog touches, so they may be
queued together with `--open-all` if throughput matters more than sequencing.

### Wired repositories with no backlog yet

These are registered, protected and gated, but have no contracts written. Each gate below
was run locally before being registered; a command absent from a gate is absent because it
fails on pre-existing faults, not because it was skipped.

| Project | Repo | Gate | Merge policy | Notes |
| --- | --- | --- | --- | --- |
| 17 mermaid-quest-academy | 9 | `npm ci`, `npx vitest run` | human_review | 270 tests green, but `npm run lint` fails with 10 errors and `npm run build` fails on a vite config type error. Fix those before widening the gate or enabling auto-merge. |
| 20 dnd-campaign-table | 10 | `npm ci`, `npx jest --testPathPatterns=tests/ --forceExit`, `npm run build` | auto_on_validation | 237 tests green, build clean. The strongest of the five. |
| 21 public-future-initiative | 11 | `npm ci`, `npm run lint`, `npm run typecheck`, `npx jest` | human_review | 81 tests green and a full gate, but the wanted work is editorial content, which no gate can validate. |
| 19 47-sunset-studios-landing-site | 12 | `npm ci`, `npm run lint`, `npm run typecheck` | human_review | No tests exist. The gate proves compilation only. |
| 18 soccer-coaching-hub | 13 | `npm ci`, `npm run lint`, `npm run build` | human_review | No tests exist. Its package `test` script is `echo "No tests yet" && exit 0` — a stub that always passes. It must never appear in a gate. |

Every gate starts with `npm ci` because the conductor runs validation commands in a fresh
clone and has no install step of its own. That also means these gates need registry access
from the execution container; the first attempt against any of them will prove whether
that exists.

`automation_enabled` is off for all five. Turning it on is an operator decision, and
nothing here is claimable until then.

## What "unattended: yes" means here

The task creates a file no other backlog item touches, in a directory the validation gate
covers, in a repository whose merge policy is `auto_on_validation`. A wrong result fails
the gate and the attempt dies; it does not reach `main`.

**It does not mean the output is guaranteed correct.** The gate proves Markdown is
structurally whole — it cannot tell whether prose is accurate. Documentation tasks carry
their facts in the contract precisely so the model formats rather than invents, but a
human or reviewing agent should still read what landed. Use the milestone review packet
for that:

```
GET /projects/14/milestones/<id>/review-packet?format=markdown
```

## Adding to the backlog

1. Write the contract with the four sections the parser requires: `CONTEXT`, `TARGET`,
   `CHANGE`, `ACCEPTANCE`. Start the file with a `# Heading`; `workq` takes the title from
   it.
2. `TARGET` uses one verb per line: `- Create <path>`, `- Modify <path>`, or
   `- Reference <path>`. Reference files become the model's read-only context.
3. Put every fact the task needs in `CONTEXT`. The model executes; it must not have to
   derive a module graph, an API, or a design.
4. Run the parser against the file, then `POST /plans/evaluate`. Both must pass.
5. Add a row to the inventory table above, including whether it is unattended-safe and
   what it depends on.
