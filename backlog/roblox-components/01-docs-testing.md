# Document component testing conventions in docs/testing.md

CONTEXT
Component specs are the only behavioural coverage this repository has, and the convention
is undocumented. A contributor or an agent adding a component has nothing to read.

The facts, all verified against the repository:

- The runner is `.lune/test.luau`, invoked as `lune run test`.
- It walks `components/`, and for each component looks in `components/<name>/tests/` for
  files matching `*.spec.luau`. Nothing outside that pattern is discovered — in
  particular, scripts under `tools/` are never covered by `lune run test`.
- If a spec module fails to load, the runner warns and exits 1. If no specs are found at
  all, it warns and exits 1.
- Each spec returns a table shaped exactly:
  `{ name = "Quests Component", tests = { { name = "...", run = function() ... end } } }`
- Each `run` function is called under `pcall`. It signals failure by raising, and the
  convention in this repository is `assert(condition, "message")`.
- The runner prints `PASS <spec name>: <test name>` or `FAIL ...`, then a final line
  `Tests: N passed, M failed, T total`.
- Components require each other by DataModel path, which Lune cannot resolve, so specs
  load modules through the harness: `local Roblox = require("../../../.lune/roblox")`
  then `local Quest = Roblox.require("ReplicatedStorage/Shared/Quest")`.
- Specs start with `--!strict`.

TARGET
- Create docs/testing.md
- Reference components/quests/tests/Quests.spec.luau

CHANGE
Document how component specs work. Cover, in this order:

1. What the runner is and how to invoke it.
2. Where specs must live for discovery, and the explicit note that `tools/` is not
   discovered, which is why `tools/` has its own gate checks instead.
3. The exact shape a spec module must return, shown as a fenced Luau block.
4. How a test signals failure, and the `assert(condition, "message")` convention.
5. Loading modules through `.lune/roblox`, shown as a fenced Luau block with the two
   require lines above, and one sentence explaining why the harness is needed.
6. What the runner prints, including the final totals line.

Luau has no `goto`, no labels (`::name::`) and no `continue` statement.

Write Markdown only. Do not add a table of contents. Do not invent APIs or behaviour
beyond the facts above. Every heading must be followed by body text before the next
heading at the same or shallower depth.

ACCEPTANCE
- docs/testing.md exists and is the only file changed.
- The spec return shape and the harness require lines both appear as fenced Luau blocks.
- The whole validation gate passes.
