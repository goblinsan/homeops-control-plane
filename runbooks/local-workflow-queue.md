# Local Workflow Queue — Operations

How to queue, run, and track directed enhancement work through the
project-dashboard + task-flow-conductor pipeline. Companion to
`docs/autonomous-workforce/directed-task-contract.md` (what a queueable
task looks like). Public-safe: substitute your dashboard URL, conductor
URL/key, and Forgejo details from your secret tooling.

Current standing posture (2026-08-10): premium escalation **disabled**
(`EXECUTION_PREMIUM_ENABLED=0`), dispatch **paused**. Everything below
operates within that: all execution is local-model only; a task whose local
attempts are exhausted settles `blocked/human_required` instead of
escalating.

## 1. Onboard a repository (once per repo)

1. **Forgejo enforcement** (server-side invariants; needs admin token):

   ```bash
   ./scripts/forgejo-branch-protection.sh \
     --owner <owner> --repo <repo> --branch main \
     --allow-user <operator> --bot conductor-bot --apply
   ```

   Add `--merge-user conductor-merge-bot` only when the repo has earned
   `auto_on_validation`.

2. **Dashboard records**:
   - Project: `automation_enabled: true`.
   - Repository: `scm_provider: forgejo`, `canonical_remote`,
     `write_enabled: true`, `pr_enabled: true`,
     `validation_commands: [...]` (the repo's real gate),
     `merge_policy: human_review`.

3. **Conductor scope**: add the project id to the `EXECUTION_PROJECT_IDS`
   entry in the conductor workload's environment (gateway admin UI →
   workloads → Save Workload → Deploy). The dispatcher only claims from
   listed projects.

## 2. Queue work

Create tasks per the directed-task contract. Non-negotiables:

- `status: open`
- `selected_repository_id` set (tasks without it are invisible to claims)
- description contains CONTEXT / TARGET / CHANGE / ACCEPTANCE

Order with `priority_score` (higher first). Queue depth is free — the
conductor claims one task at a time per repository lease at
concurrency 1.

## 3. Run

```bash
curl -X POST -H "Authorization: Bearer $CONDUCTOR_API_KEY" $CONDUCTOR_URL/execution/resume   # start draining
curl -X POST -H "Authorization: Bearer $CONDUCTOR_API_KEY" $CONDUCTOR_URL/execution/pause    # stop claiming (in-flight finishes)
curl        -H "Authorization: Bearer $CONDUCTOR_API_KEY" $CONDUCTOR_URL/execution/status    # in-flight, breakers, scope
```

Dispatch resets to paused on every conductor redeploy — resuming is always
an explicit act.

## 4. Track

One call shows the whole board:

```bash
curl "$DASHBOARD_URL/portfolio?state=queued"             # open, waiting for claim
curl "$DASHBOARD_URL/portfolio?state=running"            # claimed / in progress
curl "$DASHBOARD_URL/portfolio?state=awaiting_review"    # PR up, needs human merge
curl "$DASHBOARD_URL/portfolio?state=blocked"            # needs human decision
curl "$DASHBOARD_URL/portfolio?state=recently_completed"
```

Per-task detail (attempts, failure categories, PR links):

```bash
curl "$DASHBOARD_URL/execution/attempts?task_id=<id>"
```

## 5. Review loop (per PR, while merge_policy=human_review)

1. Review and merge (or reject) the PR in Forgejo.
2. Settle the task: `PATCH /projects/<pid>/tasks/<tid>` → `{"status": "done"}`.
3. Record the quality signal on the succeeding attempt — this is the
   evidence that later justifies auto-merge and routing decisions:

   ```bash
   curl -X PATCH -H 'Content-Type: application/json' \
     -d '{"review_outcome":"accepted_as_is"}' \
     "$DASHBOARD_URL/execution/attempts/<attemptId>"
   ```

   Outcomes: `accepted_as_is` | `accepted_with_minor_edits` |
   `accepted_with_major_edits` | `rejected` (+ optional `review_notes`).

## 6. Reading failures

| Signal | Meaning | Response |
| --- | --- | --- |
| `patch_apply_failed` | Local model produced a non-applying diff | Usually an under-specified CHANGE section or a task shape outside the directed contract — rewrite the task before blaming the model |
| `validation_failed` | Code applied but the gate failed | Read `validation_output` on the attempt; often a genuinely wrong change |
| `blocked/human_required` | Local budget exhausted | Decide: rewrite + reopen, do it by hand, or drop |
| Repo breaker open | 3 consecutive failures on one repo | Stop queueing that repo; the task contract or repo onboarding needs attention |

A rewritten task goes back to `status: open` and will be re-claimed; budget
counting is per-task, so prefer a fresh task over endlessly reopening one
with a burned budget.

## 7. Agent interface (token-free lifecycle automation)

`scripts/workq.sh` wraps the entire lifecycle in deterministic commands so
any agent, cron job, or human can operate the queue without LLM involvement.
Configure `WORKQ_DASHBOARD_URL`, `WORKQ_CONDUCTOR_URL`,
`WORKQ_CONDUCTOR_KEY`, and `WORKQ_CONTRACT_PARSER` in the environment (keep
them in a private env file). `WORKQ_CONTRACT_PARSER` must point at an
executable directed-task parser. For the local conductor checkout, use the
wrapper at `<task-flow-conductor>/scripts/parse-directed-task`.

```bash
workq.sh queue <projectId> <repoId> task-1.md task-2.md task-3.md \
        --priority 300 --complexity low --label enhancement
workq.sh add <projectId> <repoId> --title "…" --description-file task.md \
        --priority 300 --complexity low --label enhancement
workq.sh board                 # whole portfolio at a glance
workq.sh attempts <taskId>     # attempt history, failure categories, PR links
workq.sh review <pid> <tid> accepted_as_is "optional notes"
workq.sh reopen <pid> <tid>    # requeue (also used to unblock a held task)
workq.sh resume|pause|status   # dispatch control
```

`add` is fail-closed: it calls `WORKQ_CONTRACT_PARSER` and refuses to create a
dashboard task unless the parser accepts the full directed-task contract. The
old grep-only section check is intentionally gone. Valid tasks are created with
durable `target_entries`, `target_files`, and `reference_files` metadata for
the local backend. `target_entries` is the execution authority for create vs.
modify behavior; the backend must not re-read file lists from task prose.

Prefer `queue` for normal use. It accepts one or more markdown task files,
derives each title from the first `# Heading` in the file, and creates the
tasks after the same parser-gated intake as `add`. When multiple files are
provided, only the first task is created `open`; successors are created
`blocked` by default so a chain cannot run against stale `main`. Pass
`--open-all` only for independent tasks that can safely run in parallel.

**Sequential tasks on one file:** worktrees clone `main`, so a task that
edits a file created by an earlier task must not become claimable until the
earlier PR is *merged*. Queue the first task `open` and the successors
`blocked`; after each merge + `review`, `reopen` the next one. `workq queue`
does the initial open/blocked setup for you.

## 8. Delegating the queue to another agent

The queue is meant to be operated by whichever agent is on hand — Claude, Codex, Gemini,
a cron job, or the operator. Nothing in the lifecycle needs an LLM. This section is the
whole contract for that hand-off.

### What the delegate needs

- `scripts/workq.sh` on PATH, with `WORKQ_DASHBOARD_URL`, `WORKQ_CONDUCTOR_URL`,
  `WORKQ_CONDUCTOR_KEY` and `WORKQ_CONTRACT_PARSER` set (see section 7).
- `backlog/` — vetted contracts, already through the parser and `/plans/evaluate`.
- `backlog/README.md` — the inventory, and which items are unattended-safe.

### The loop

```bash
workq.sh status                       # dispatch on? anything in flight?
workq.sh board                        # what is already running or awaiting review
workq.sh queue <projectId> <repoId> backlog/<repo>/<file>.md \
        --priority <n> --complexity low --label unattended-batch
workq.sh board                        # confirm the claim
workq.sh attempts <taskId>            # on failure: category, PR link, history
```

Under `merge_policy=auto_on_validation` a successful task reaches `done` on its own and
needs no review step. Under `human_review` it stops at `in_review` and needs
`workq.sh review <pid> <tid> <outcome>`.

### Rules for a delegate

1. **Only queue from `backlog/`.** Authoring a contract at queue time skips both intake
   gates. If new work is needed, write it into `backlog/`, run the parser and the
   evaluator, and queue it on the next pass.
2. **Respect the unattended column.** An item marked `no` needs a human before it runs.
3. **One chain at a time.** If two contracts touch the same file, queue the first `open`
   and let `workq queue` hold the rest `blocked`; worktrees clone `main`, so a successor
   queued early runs against stale code.
4. **Stop on the second consecutive failure.** Two failures in a row is a systemic problem
   — a broken gate, a stale contract, an unreachable model — not a task-level one. Report
   the failure categories from `workq.sh attempts` and stop queueing.
5. **Never widen the gate to make something pass.** If a task fails validation, the task
   is wrong until proven otherwise. Changing `validation_commands` to get a green run
   removes the only thing standing between a bad change and `main`.
6. **Do not enable dispatch or change merge policy.** `workq.sh resume` and repository
   posture are operator decisions.

### Reporting back

After a batch, report: what was queued, the terminal state of each task, PR links for
anything merged, and failure categories for anything that did not. For a milestone's worth
of work, fetch the review packet instead of narrating:

```
GET /projects/<projectId>/milestones/<milestoneId>/review-packet?format=markdown
```

That document is self-contained and designed to be read by a model. Findings go back via
`POST /projects/<projectId>/milestones/<milestoneId>/review-findings`; an accepted finding
becomes a blocked task rather than running immediately.
