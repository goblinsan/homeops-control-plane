# Control Workflows Runbook

Control workflows are non-code automation paths for observing, summarizing, and
prioritizing portfolio work. They must not mutate repositories, create
implementation tasks, or dispatch coding attempts without an explicit operator
acceptance action.

## Modes

- Deterministic observation may run while all LLM control workflows are off.
- Failure analysis uses bounded evidence packets and may be enabled for blocked
  or human-required runs once summaries are useful in review.
- Planning/design outputs remain draft packets until accepted by an operator.
- Backlog prioritization remains suggestive and must not enqueue work directly.

## Disable LLM Control Workflows

Leave deterministic observation enabled, but disable automatic LLM-backed
control workflows by policy/config. Implementation dispatch and control
workflow LLM calls are separate concerns; turning off control LLM calls must not
disable lease sweeps, breaker checks, or deterministic status observation.

## Validation Cost Metrics

The runner remains the pre-push validation authority. Local backends may also
validate inside their repair loop, so successful attempts can show duplicate
validation:

- backend validation: local backend validated the merged rewrite set
- runner validation: final pre-push validation before commit/PR
- duplicate validation: both happened for the same attempt

Use portfolio observation metrics to decide whether duplicated validation is a
material wall-time cost before changing behavior. Do not skip runner validation
until there is a reviewed `validated`/`validation_evidence` policy with
spot-check coverage.

## Rollout Gates

- Observation sweeps must report only transition-backed findings and bounded
  derived metrics.
- Summary generation failures must not alter implementation attempt status.
- Planner output must stay in markdown/artifact form until accepted.
- Prioritization suggestions must remain non-claimable roadmap state.
- Any control workflow gaining SCM write capability is a stop condition.

## Operator Checks

1. Check current observations for active findings and slow validation gates.
2. Review failed summaries before enabling automatic summaries more broadly.
3. Use backlog prioritization as an ordering aid, not as queue mutation.
4. Keep control-surface repositories in manual-batch posture unless explicitly
   running a reviewed batch.
