# Directed Task Contract

The local execution flow exists for **highly directed work**: executing a
plan against a known architecture with an explicit code contract. It is not
for vague briefs, open-ended problem solving, or novel solution design.
Every task queued for the local system must satisfy this contract; a task
that cannot be written this way is not local work yet — it needs a planning
pass first (human or premium), whose *output* becomes the directed task.

## The contract

A queued task's description must contain all four sections:

```text
CONTEXT
  What this repo/module does, in two sentences or less, plus anything the
  implementer must know that is not visible in the target files.

TARGET
  The exact file(s) to create or modify. For modifications, name the
  functions/sections being touched. Tasks touching more than ~3 files are
  suspect: split them or route them for planning.

CHANGE
  The precise contract of the change: signatures, types, expected behavior,
  and (for new code) which existing patterns/components to imitate — named,
  not implied. If integration with existing code is required, state the
  import contract explicitly (what to import, from where). The local model
  executes stated graphs; it does not derive them.

ACCEPTANCE
  The objective pass condition, phrased as the validation command outcome
  (e.g. "npm run typecheck && npm test exits 0", "node test.js exits 0").
  If acceptance requires a new test, the CHANGE section specifies that test.
```

## Field mapping (project-dashboard)

| Field | Rule |
| --- | --- |
| `title` | Imperative summary of CHANGE, ≤ 80 chars |
| `description` | The four sections above |
| `selected_repository_id` | **Required** — the claim query skips tasks without it, silently |
| `execution_complexity` | `low` for contract-complete single-file work; `medium` when imitation of existing patterns carries part of the load; `high` reserved (routes premium when premium is enabled — it is currently disabled) |
| `priority_score` | Higher claims first; use it to order the queue |
| `labels` | Stream tags for tracking (e.g. `enhancement`, `roblox-components`) |

## What not to queue

- Anything on a repo whose architecture is still moving (work in flight —
  e.g. AssetForge as of 2026-08). Hands-off execution on an unstable
  contract produces churn, not progress.
- Cross-file structural derivation ("wire this into the app") without an
  explicit import contract — the measured local-model weakness.
- Design *creation* (visual identity, API shape invention). Design
  *execution* against a stated spec is fine.
- Refactors phrased as outcomes ("clean this up"). State the target shape
  or don't queue it.

## Review posture

New repositories start at `merge_policy: human_review`. A repo earns
`auto_on_validation` through a streak of `accepted_as_is` review outcomes
on that repo — not by analogy to another repo.
