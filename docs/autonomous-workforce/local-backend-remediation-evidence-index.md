# Local Backend Remediation Evidence Index

This index anchors the replay corpus for the local backend remediation. It
intentionally contains no private URLs, hostnames, credentials, or topology.

## Recorded Attempts

| Attempt | Evidence role |
| --- | --- |
| 18 | Early local execution failure showing the thin diff path could not reliably produce applicable edits. |
| 20 | Follow-on local failure in the same failure class, useful for checking repeated-attempt behavior. |
| 23 | Existing-file edit failure used to validate that target context must be loaded before model execution. |
| 25 | Parser/application failure representative for full-file rewrite regression tests. |
| 27 | Validation-failure case for repair-loop diagnostics and artifact preservation. |
| 28 | Local failure showing model output must be persisted even when application fails. |
| 32-41 | Consecutive dogfood failures on existing-file dashboard work; primary corpus for proving the remediated local path does not fall back to fragile unified diffs. |

## Positive Control

Task 164 is the known positive-control new-file case. Its successful merge
means the live acceptance task should target wiring the existing UI shell into
server registration plus route tests, exercising the same existing-file failure
class that broke tasks 165-168.

## Live Acceptance Evidence

The R8 acceptance run used an isolated remediation validation project and
repository with premium execution disabled.

| Task | Attempt | Evidence role |
| --- | --- | --- |
| 7 | 14 | Successful local-backend acceptance run. Validation passed, a Forgejo PR was created, and the human review outcome was recorded as `accepted_as_is` after merge. |
| 34 | 34 | Kill-test attempt. The conductor was terminated mid-attempt, the persisted lease expired, restart recovery swept the stale attempt, and no PR was created for the interrupted run. |

## Replay Interpretation

Attempts 18, 20, 23, 25, 27, 28, and 32-41 do not have persisted prompts or
raw model outputs from the original failures. Replay fixtures must therefore
be reconstructed from durable task metadata, repository state, validation
output, and failure categories, with synthetic model responses used for
hermetic parser/application coverage.
