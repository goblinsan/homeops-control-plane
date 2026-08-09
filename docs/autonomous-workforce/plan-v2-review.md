# Review of Autonomous Workforce Plan v2

## Verdict

**Proceed with modifications.**

Plan v2 is materially stronger than v1 and should become the new
architecture baseline after the targeted changes below are incorporated.

The strongest improvement is moving critical safety boundaries out of
`task-flow-conductor` and into Forgejo configuration, credential
capabilities, and other enforcement layers. "Never push main" and "never
merge" should be structural constraints rather than behavioral
expectations.

The MVP now has the right first proof:

> Can a human-approved task safely become a validated, review-ready
> Forgejo PR without manual coding?

## Review of Changes from v1

1.  **Server-side safety enforcement --- ACCEPT.** Forgejo branch
    protection plus scoped credentials is the correct primary
    enforcement layer. Keep conductor checks as defense in depth.
2.  **Validation as part of an attempt --- ACCEPT.** Validation belongs
    within an implementation attempt, not as a sibling attempt.
3.  **Concurrency/leasing/recovery in Phase 1 --- ACCEPT WITH
    MODIFICATION.** Leasing and idempotency belong in the initial model.
    Also establish structural repository exclusivity.
4.  **Codex removed from MVP --- ACCEPT.** One premium backend is enough
    to prove escalation.
5.  **Local-only pilot before premium --- STRONGLY ACCEPT.** Prove the
    complete execution/review pipeline before premium execution.
6.  **Single portfolio endpoint --- ACCEPT.** `GET /portfolio?state=...`
    is cleaner.
7.  **Repository-field simplification --- ACCEPT.** Dropping
    `requires_human_merge` and `migration_status` is appropriate.
    `auto_deploy_on_main` should remain advisory only.
8.  **Derived review-ready state --- ACCEPT.** Removing
    `execution_disposition` avoids dual-written state.
9.  **Failure taxonomy --- ACCEPT.** The additions are useful; avoid
    over-optimizing taxonomy before real execution data exists.
10. **Budgets/circuit breakers --- ACCEPT.** These belong in the
    architecture.
11. **Minimum viable isolation --- ACCEPT WITH CAUTION.** Dedicated
    user, isolated checkout, and secret scanning are credible MVP
    controls, but host shell execution remains a risk. Container
    isolation should remain an early hardening step.
12. **Idempotent/cancellable backend execution --- ACCEPT CONCEPT,
    MODIFY RESPONSIBILITY.** Cancellation belongs in the backend
    contract. Idempotency primarily belongs to the conductor-owned
    attempt lifecycle.
13. **SCM PR lookup/no merge method --- ACCEPT.** PR lookup is necessary
    for recovery; keeping merge absent is a strong safety property.
14. **Autonomous task generation out of scope --- STRONGLY ACCEPT.**
    Execution and invention of work are different trust boundaries.

## Required Architecture Modifications

### 1. Introduce an AttemptRunner

The current design puts too much lifecycle responsibility into
`ExecutionBackend.execute()`.

A backend should own **model execution**, not worktree/SCM
reconciliation.

Recommended decomposition:

``` text
Conductor Scheduler
        |
        v
AttemptRunner
   |-- WorktreeManager
   |-- ExecutionBackend
   |-- Validator
   |-- SecretScanner
   |-- GitOperations
   `-- ScmProvider
        |
        v
project-dashboard persistence
```

`AttemptRunner` owns the idempotent lifecycle:

``` text
prepare worktree
-> invoke backend
-> inspect changes
-> validate
-> secret scan
-> commit
-> push
-> create/recover PR
-> persist result
```

`ExecutionBackend` should own only model-specific implementation.
Reconciliation of worktrees, branches, pushes, and PRs belongs to
`AttemptRunner`.

### 2. Distinguish Blocked Attempts from Failed Attempts

Do not classify every unsuccessful disposition as `failed`. Human action
or policy blocking is not necessarily an execution failure and will
distort metrics.

Recommended attempt states:

``` text
claimed
running
succeeded
failed
cancelled
escalated
blocked
```

Examples:

``` text
blocked + human_required
blocked + policy_blocked
blocked + budget_exhausted
```

versus:

``` text
failed + validation_failed
failed + model_timeout
failed + capability_gap
```

### 3. Keep Claim and Lease Mutation Behind project-dashboard

`project-dashboard` owns durable portfolio state. Avoid giving
`task-flow-conductor` direct database ownership just to implement
transactional claims.

Prefer:

``` text
task-flow-conductor
        |
        v
POST /execution/claims
        |
        v
project-dashboard
        |
        v
transaction / SKIP LOCKED
```

The conductor determines policy and eligibility; the dashboard performs
durable atomic state mutation. This preserves service ownership and
avoids coupling the conductor to dashboard database internals.

### 4. Make Repository Coordination Explicit

"One active attempt per repository" is correct, but exclusivity should
be enforced structurally rather than solely by dispatcher behavior.

Consider a repository execution lease equivalent to:

``` text
repository_id
lease_owner
lease_expires_at
```

This can coordinate execution, recovery, branch cleanup, repository
refresh, and future rebase/update operations. At minimum, explicitly
distinguish attempt lease/liveness from repository execution
exclusivity.

### 5. Keep SCM Credentials Out of the Coding Agent

The proposed attempt process receives a repo-scoped Forgejo token.
Tighten this boundary.

A tool-holding coding agent with shell access may inspect its
environment. Prefer:

``` text
Coding Agent
    |
    | modifies isolated worktree
    v
filesystem
    |
    v
Trusted AttemptRunner / SCM helper
    |
    | holds Forgejo credential
    v
Forgejo
```

The coding backend should not need the SCM credential. Where practical,
provider credentials should likewise be held by a trusted provider
wrapper rather than exposed to the general coding shell.

Make this an explicit principle:

**The coding process has less privilege than the orchestration
process.**

## Safety Assessment

Strong v2 controls that should remain:

-   protected default branches
-   repo-scoped bot identities
-   no merge capability in `ScmProvider`
-   explicit repository write enablement
-   deploy-hook audit
-   secret-diff scanning
-   kill switch
-   premium spend circuit breaker
-   repository failure breaker
-   global failure-rate breaker
-   isolated fresh worktree
-   dedicated non-privileged execution user
-   repository/task content treated as untrusted input

The primary remaining refinement is privilege separation between coding
execution and trusted orchestration.

## Recommended Implementation Order

### Phase 1 --- Schema and Persistence

Keep the proposed Phase 1, including leasing/idempotency schema.
Preserve the API ownership boundary for transactional claims.

### Phase 2 --- Enforcement Setup

Keep branch protection, scoped bot identities, deploy-hook audit, and
verification. No autonomous SCM write should occur before this succeeds.

### Phase 3A --- AttemptRunner and Isolation

Introduce `AttemptRunner`, `WorktreeManager`, dedicated execution
identity, attempt/repository coordination, secret scanning, and trusted
Git/SCM operations.

### Phase 3B --- LocalExecutionBackend

Wrap the existing local persona workflow behind the provider-neutral
backend contract.

### Phase 3C --- Forgejo Adapter

Implement create PR, find PR by branch, get PR, and recovery/idempotency
behavior.

### Phase 4 --- Execution Policy and Attempt Lifecycle

Add policy resolution, dispatch claims, leases/heartbeats, crash
recovery, failure classification, circuit breakers, and kill switch.

### Phase 5 --- Local-Only Pilot

Prove:

``` text
human-authored task
-> claim
-> isolated worktree
-> local execution
-> validation
-> secret scan
-> trusted branch push
-> Forgejo PR
-> dashboard review-ready
```

Require no manual coding intervention and test recovery by killing the
conductor mid-attempt.

### Phase 6 --- Claude Backend and Escalation

Only after the local pipeline is reliable: Claude backend, cancellation,
token/cost caps, parent/child escalation attempts, and premium daily
budget.

### Phase 7 --- Controlled Portfolio Rollout

Gradually enable HomeOps/factory improvement, Arremate/revenue, and
AssetForge/creative. Codex remains post-MVP. Autonomous task generation
remains separately reviewed and out of scope.

## Open Question Recommendations

**Dedicated execution user:** use it from the first local pilot. The
pilot should prove the production-shaped isolation model.

**Existing runs model:** do not modify `runs` speculatively. Start with
`task_execution_attempts.run_id` and change the runs model only if
implementation demonstrates a real problem.

**Failure-breaker threshold:** configuration-driven and tuned from pilot
evidence.

**Daily premium cap:** configuration-driven; this is an operating
decision rather than an architecture decision.

## Final Assessment

Plan v2 should supersede v1 after incorporating these modifications:

1.  Introduce a conductor-owned `AttemptRunner`.
2.  Keep `ExecutionBackend` focused on model execution.
3.  Distinguish `blocked` from genuine execution `failed`.
4.  Keep transactional claim/lease mutation behind the
    `project-dashboard` API boundary.
5.  Explicitly model repository execution coordination.
6.  Keep Forgejo credentials out of the coding-agent process whenever
    practical.

The resulting decomposition is:

``` text
project-dashboard
    durable state

task-flow-conductor
    scheduling and policy

AttemptRunner
    idempotent execution lifecycle

ExecutionBackend
    model-specific coding execution

Forgejo
    protected SCM/review boundary

human
    merge/deployment approval
```

With those refinements, the architecture is ready to move from design
into Phase 1 implementation.
