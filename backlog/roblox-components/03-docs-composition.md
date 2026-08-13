# Document component composition in docs/composition.md

CONTEXT
The point of this library is that a workflow composes game features from existing
components rather than authoring Luau from scratch. The catalog index and the manifests
make that possible, but nothing explains the composition procedure itself.

The facts, all verified against the repository:

- Every component carries a `component.yaml` three-face contract, documented in
  `docs/component-manifest.md`.
- `provides` declares what a component exposes: `shared` modules, `net` events,
  `contracts` (verbatim call signatures) and `behavior` statements.
- `requires` declares what it needs: `interfaces` (a named role plus its contract, which
  the consumer does not import — it is supplied), `components` (hard dependencies), and
  `contracts` (verbatim calls it will make against another component's provider).
- `tools/emit-catalog-index.luau` writes `catalog-index.json`, one entry per component
  with its `provides` and `requires` copied verbatim. Its format is documented in
  `docs/catalog-index.md`.
- The `net` component is the only messaging path: components do not touch RemoteEvents
  directly. Its call surface is `Net.ensureRemote(name)`, `Net.ensureRemotes(names)`,
  `Net.fireClient(name, player, ...)`, `Net.fireAllClients(name, ...)`,
  `Net.onServerEvent(name, handler)`, `Net.fireServer(name, ...)` and
  `Net.onClientEvent(name, handler)`.
- Outbound remotes must be predeclared at server startup with `Net.ensureRemote` or
  `Net.ensureRemotes`, otherwise a client `Net.onClientEvent` can race remote creation
  and block forever.
- A required interface is satisfied by supplying an implementation, not by importing one.
  The `quests` component, for example, requires a `QuestCatalog` and a `RewardGranter`
  rather than importing the components that provide them.

TARGET
- Create docs/composition.md
- Reference components/net/component.yaml

CHANGE
Document how to compose a feature from components. Cover, in this order:

1. The premise: features are composed from existing components; authoring new Luau is the
   exception.
2. Reading `catalog-index.json` to discover what exists, pointing at
   `docs/catalog-index.md` for the format.
3. The three-face contract as the selection unit, explaining `provides` and `requires` and
   pointing at `docs/component-manifest.md`.
4. Satisfying `requires.interfaces` by supplying an implementation rather than importing
   one, using the `quests` component's `QuestCatalog` and `RewardGranter` as the example.
5. Messaging through `net` only, listing the seven Net calls as a fenced Luau block, and
   stating the predeclare rule and the consequence of skipping it.
6. A short "Composition checklist" of five steps: find candidate components in the index,
   read their contracts, satisfy every required interface, predeclare any outbound
   remotes, and run the validation gate.

Luau has no `goto`, no labels (`::name::`) and no `continue` statement.

Write Markdown only. Do not add a table of contents. Do not invent APIs or behaviour
beyond the facts above. Every heading must be followed by body text before the next
heading at the same or shallower depth.

ACCEPTANCE
- docs/composition.md exists and is the only file changed.
- The seven Net calls appear as a fenced Luau block and the predeclare rule is stated.
- The whole validation gate passes.
