# Review — Autonomous Workforce Status and Next Steps

## Verdict

**Approve N1–N4 with minor sequencing changes.**

The MVP should now be considered complete. The live pilots proved both critical paths: human-approved task → local execution → validation → Forgejo PR → human merge, and local failure → classified Claude escalation → validated PR → human merge.

The defects found during the pilots—missing file context, heartbeat/lease mismatch, missing status settling, zero-work attempts consuming attempts, and incorrect premium accounting—are exactly the lifecycle issues that live execution should expose. Fixing them with tests materially increases confidence.

## N1 — Post-pilot hygiene

**Accept; do immediately.**

Rotate both identified credentials before further live execution. Restore `EXECUTION_MAX_ATTEMPTS_PER_TASK` to its normal default. The proposed standing posture is reasonable: premium enabled, dispatch paused.

Keep `pilot-sandbox` permanently. It is now useful execution-platform infrastructure: a safe target for conductor upgrades, model changes, Forgejo changes, credential rotation, recovery tests, secret scanning, and PR creation.

## N2 — Move conductor to a node

**Accept; this is now the critical path.**

The Mac deployment retains pilot shortcuts that conflict with the intended operating model. The production shape should use a dedicated service identity, isolated checkout root, scoped Forgejo identities, and a dedicated provider credential.

Using a dedicated Anthropic API key rather than subscription OAuth is correct because it creates an independently revocable, measurable, budgetable, and auditable identity.

Add one node acceptance criterion: repeat a real crash/recovery test before retiring the Mac conductor.

Recommended node validation:

```text
deploy
-> npm run pilot:e2e
-> live pilot-sandbox smoke task
-> kill conductor during controlled attempt
-> allow lease to expire
-> restart/recover
-> verify reconciliation and no duplicate side effects
-> retire Mac conductor
```

## N3 — Close deliberate simplifications

**Accept, but split the sequencing.**

### N3.1 — Per-repository validation

Promote this to a rollout prerequisite.

Environment-level validation is acceptable for one pilot repository but not once a second real repository is enabled.

Required sequence:

```text
node productionized
-> repository/workflow validation wired
-> AssetForge enabled
```

### N3.2 — Attempt artifacts

Accept, but do not block AssetForge rollout. Publishing backend-selection, validation, and premium-summary artifacts via `artifacts.attempt_id` will improve auditability and debugging, but existing attempt records provide enough visibility for controlled real work.

### N3.3 — Dashboard affordances

Accept, non-blocking. A mark-done action and portfolio UI improve operations, but they are usability work rather than a safety prerequisite.

## N4 — Widen rollout

**Accept, with a stronger definition of the AssetForge stage.**

AssetForge should now receive real work rather than another smoke test. Start with roughly 3–5 deliberately selected tasks at concurrency 1. They should be independently scoped, useful, low-risk, and objectively testable where practical.

Evaluate the batch using local success rate, failure categories, escalation rate, Claude success after escalation, time-to-review-ready, validation success, premium cost, human review effort, and actual usefulness.

The key question has changed from “Can the system create a PR?” to:

> **Does the system create useful project progress while the operator is doing something else?**

Keep global concurrency at 1 initially. Increase it after two different repositories have demonstrated predictable execution behavior, not merely after several AssetForge successes.

Recommended rollout:

```text
AssetForge
-> several useful tasks
-> HomeOps
-> several useful tasks
-> persist/rebuild breaker state
-> concurrency 2
-> Arremate
-> consider concurrency 3 from evidence
```

## Additional recommendation — Capture human review outcomes

Machine telemetry is strong, but the next stage needs the most important quality signal: what happened during human review.

Add a lightweight PR outcome:

```text
accepted_as_is
accepted_with_minor_edits
accepted_with_major_edits
rejected
```

Optionally persist a short reason.

A technically successful PR is not necessarily valuable work. Future local/Claude/Codex comparisons should account for human review burden as well as validation success, latency, and provider cost.

For example, a $0 local change requiring a major rewrite can be economically worse than a $0.13 Claude change accepted as-is.

This can remain simple; no sophisticated scoring system is needed yet.

## Decisions

- **D1:** Accept — premium enabled, dispatch paused.
- **D2:** Accept — retain `pilot-sandbox` permanently.
- **D3:** Leave node/deployment choice to the existing HomeOps deployment model.
- **D4:** Accept — dedicated Anthropic API key.
- **D5:** Accept initial $10/day and $3/attempt limits; keep them configuration-driven and tune from evidence.
- **D6:** Accept — AssetForge first.

## N5 — Post-MVP tracks

Keep all N5 items deferred for now.

Container-per-attempt remains the correct isolation end state, with increasing priority as repository count and concurrency grow.

Do not implement Codex yet. Gather enough local/Claude execution data to identify what problem a second premium provider should solve.

Continue to defer `agent-service` integration unless actual duplication or operational pain emerges.

Keep autonomous task generation explicitly out of scope. Executing approved work and deciding what work should exist are different trust models.

## Recommended immediate sequence

```text
N1
hygiene + credential rotation
        |
        v
N2
production node deployment
        |
        v
pilot:e2e + live smoke + crash/recovery smoke
        |
        v
N3.1
per-repository/workflow validation
        |
        v
AssetForge: 3–5 real tasks, concurrency 1
        |
        +--> human PR outcome capture
        +--> attempt artifacts
        +--> portfolio UI improvements
        |
        v
HomeOps: real tasks, concurrency 1
        |
        v
persist/rebuild breaker state
        |
        v
concurrency 2
        |
        v
Arremate
```

## Change in project objective

The architecture project has achieved its MVP objective. The system has demonstrated durable portfolio state, autonomous task claiming, local execution, validation, protected SCM writes, PR creation, human review boundaries, premium escalation, cost accounting, failure classification, recovery behavior, and circuit breakers.

The next phase should stop optimizing for **building the autonomous workforce** and begin optimizing for **using the autonomous workforce**.

A suitable next objective is:

> **Keep multiple side-work streams making measurable, useful progress without requiring the operator to personally perform their implementation work.**

Judge the system increasingly by useful PRs produced, human review effort, project milestones advanced, execution reliability, time-to-review-ready, and premium cost per accepted change.

## Final verdict

**Approve N1–N4 with the sequencing changes above.**

Immediate priorities:

1. Clean up pilot credentials/configuration.
2. Productionize the conductor on its node.
3. Repeat smoke and recovery validation there.
4. Move validation configuration to repository/workflow scope.
5. Start giving AssetForge real work.
6. Capture human review outcomes.
7. Widen to a second repository before increasing concurrency.

No additional architecture work is required before those steps.

The most important next milestone is:

> **Several useful AssetForge changes appear as validated PRs while the operator spends no time implementing them.**
