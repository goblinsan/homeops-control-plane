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

### 47-sunset-studios-landing-site (project 19, repository 12)

Repository posture: `auto_on_validation`, dispatch `background_ok`, automation on. The gate
is `npm ci --include=dev`, `npm run lint`, `npm run typecheck`, `npm run build`. The site is
fully static, so a successful build prerenders every page — that is real coverage for this
repository, not a stand-in for tests it does not have.

| File | Creates | Unattended | Depends on |
| --- | --- | --- | --- |
| `01-docs-layout-primitives.md` | `docs/layout-primitives.md` | delivered | — |

Delivered by task 209 / attempt 104 and auto-merged: all four gate commands passed, the
document was checked against the source and its props, class names and five size mappings
are correct. Kept here as the worked example of a contract that survives the 14B.

### soccer-coaching-hub (project 18, repository 13)

Repository posture: `auto_on_validation`, dispatch `background_ok`, automation on. The gate
is `npm ci --include=dev`, `npm run lint`, `npm run build`, `npm test`.

| File | Creates | Unattended | Depends on |
| --- | --- | --- | --- |
| `01-docs-repositories.md` | `docs/repositories.md` | yes | — |

Written and pre-flighted but never delivered: its two attempts predate the gate repair, so
they failed on the environment rather than on the contract. Re-queue it as the first check
that the repair holds on this repository.

### Wired repositories with no backlog yet

Three of the five still have no contract written. All five are registered, protected,
gated, on `auto_on_validation`, and automated. Every gate below was run locally to green
before the policy was set — a gate that cannot pass makes every task fail on faults it did
not cause.

| Project | Repo | Gate | Coverage it proves |
| --- | --- | --- | --- |
| 17 mermaid-quest-academy | 9 | `npm ci`, lint, build, `npx vitest run` | 270 tests, plus compile and lint |
| 20 dnd-campaign-table | 10 | `npm ci`, jest, build | 237 tests, plus compile |
| 21 public-future-initiative | 11 | `npm ci`, lint, typecheck, `npm run validate`, `npm test` | 81 tests, plus frontmatter validation over `content/` |
| 19 47-sunset-studios-landing-site | 12 | `npm ci`, lint, typecheck, build | Static prerender of every page; a broken component fails the build |
| 18 soccer-coaching-hub | 13 | `npm ci`, lint, build, `npm test` | 11 repository tests, plus compile |

Every gate starts with `npm ci --include=dev` because the conductor runs validation
commands in a fresh clone and has no install step of its own. The `--include=dev` is not
decoration — see below.

#### Registry access is proven; `NODE_ENV` was the real problem

Attempt 103 on repository 12 settled the open question. The conductor's in-loop validator
runs a repository's commands in order and returns on the first one that fails. It reported
a failure for `npm run lint`, the *second* command, which is only reachable if the first
one passed. So **`npm ci` reaches the registry from the execution container and exits 0.**
There is no egress problem.

The failure it did report was this:

    > eslint src --ext .ts,.tsx
    sh: 1: eslint: not found

The conductor image sets `ENV NODE_ENV=production` (its Dockerfile runtime stage). Under
that variable npm omits `devDependencies`, so a plain `npm ci` installs successfully and
still leaves no `eslint`, no `tsc`, no `vitest`, no `jest`. Reproduced locally against a
fresh clone:

| command | exit | `eslint` | `tsc` | `next` |
| --- | --- | --- | --- | --- |
| `NODE_ENV=production npm ci` | 0 | absent | absent | present |
| `npm ci` | 0 | present | present | present |
| `NODE_ENV=production npm ci --include=dev` | 0 | present | present | present |

Every gate that shells out to a dev-dependency binary was therefore unpassable, while
`npm ci` itself reported success. All five gates now use `npm ci --include=dev`.

This also explains a failure that looked like a model defect. When a validation command
fails, the local backend feeds the diagnostics back to the model as a repair prompt. Told
to fix `eslint: not found`, the only lever the model has is `package.json`, so it rewrote
it — and the non-target-file guard correctly rejected that, three rounds per attempt,
across two different repositories. The guard behaved correctly; the model was responding
rationally to an impossible instruction. **An environmental failure must not be handed to
the model as a repair prompt.**

Three of the five needed repair before they could be gated honestly, and the repairs are
worth knowing about:

- **mermaid-quest-academy** had 270 passing tests alongside ten lint errors and eight type
  errors. Tests passing said nothing about whether the project built.
- **soccer-coaching-hub** shipped `"test": "echo \"No tests yet\" && exit 0"`. Gating on
  it would have reported success forever. It now has eleven tests covering the
  repositories' defensive-copy contract, verified by sabotage.
- **public-future-initiative** has an editorial content surface under `content/`, which no
  code test touches. `npm run validate` checks required frontmatter across every content
  file, so content changes are structurally guarded — though nothing can validate whether
  the prose is true.

`automation_enabled` is on for all five as of 2026-08-13, and conductor dispatch is
running. Both halves of the claim path are therefore open: a task queued against any of
these repositories with a `selected_repository_id` set will be claimed on the next
dispatch cadence without further approval. Queue deliberately.

#### Both failure breakers now recover on their own

They did not, until 2026-08-13. A repository breaker opened after three consecutive
failures and cleared only by `resetRepo` — never called anywhere — or by a success the open
breaker itself prevented. The global breaker halted all dispatch, so no attempt ran, no
outcome was recorded, and its window never changed. Three bad tasks in a row could retire a
repository, or the whole queue, until someone restarted the service.

Both now open for a cooldown and then go half-open: the next attempt is allowed through and
its outcome decides whether the breaker closes or re-arms with a doubled cooldown, capped at
an hour. Defaults are ten minutes per repository and five globally, both env-tunable. The
global breaker also closes early if attempts already in flight roll the failure ratio back
under the threshold. A breaker-open repository no longer parks its task in `blocked`; the
task returns to the queue and waits the cooldown out.

`GET /execution/status` now reports `global_retry_at` and `repository_retry_at`, so an
operator can see when each breaker will next be probed. To clear one immediately:

```bash
curl -X POST "$WORKQ_CONDUCTOR_URL/execution/breakers/reset" \
  -H "Authorization: Bearer $WORKQ_CONDUCTOR_KEY" \
  -H 'Content-Type: application/json' -d '{"repository_id": 13}'
```

An empty body clears every breaker.

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
