# Document the Rojo/Lune harness in docs/harness.md

CONTEXT
The repository carries a Rojo/Lune harness that lets components be exercised as if they
were composed into one game, and it is undocumented.

The facts, all verified against the repository:

- `default.project.json` is a Rojo project that maps each component's `src` files into a
  DataModel tree. Shared modules land under `ReplicatedStorage.Shared`, for example
  `components/zones/src/shared/WorldZones.luau` becomes
  `ReplicatedStorage.Shared.WorldZones`.
- That mapping is what lets a component require another by DataModel path rather than by
  file path, which is how the code would look inside a real Roblox game.
- `harness/` holds bootstrap scripts that drive components in a running place:
  `harness/src/server/HarnessBootstrap.server.luau`,
  `harness/src/server/FishingHarness.server.luau`, and
  `harness/src/client/CreditsHarness.client.luau`.
- `harness/generated/AttributionCatalog.luau` is generated, not hand written.
- `harness.rbxlx` is the place file the harness is served into.
- The toolchain is pinned in `rokit.toml`: rojo, lune, selene, stylua and luau-lsp.
- Type checking uses the Rojo sourcemap:
  `rojo sourcemap default.project.json --output sourcemap.json`
  then `luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json components`.

TARGET
- Create docs/harness.md
- Reference default.project.json

CHANGE
Document the harness. Cover, in this order:

1. What the harness is for: exercising components as a composed game rather than as
   isolated files.
2. How `default.project.json` maps component sources into the DataModel, with the
   WorldZones example, and why that mapping matters for how components require each other.
3. What lives under `harness/`, naming the three bootstrap scripts and their roles
   (server bootstrap, a fishing harness, a client credits harness), and noting that
   `harness/generated/` is generated rather than hand written.
4. The pinned toolchain from `rokit.toml`.
5. Type checking, showing the sourcemap and analyze commands as a fenced bash block.

Luau has no `goto`, no labels (`::name::`) and no `continue` statement.

Write Markdown only. Do not add a table of contents. Do not invent APIs, files or
behaviour beyond the facts above. Every heading must be followed by body text before the
next heading at the same or shallower depth.

ACCEPTANCE
- docs/harness.md exists and is the only file changed.
- All three harness scripts are named, and the type-check commands appear as a fenced block.
- The whole validation gate passes.
