# Document the in-memory repository layer and its copy contract

CONTEXT

`soccer-coaching-hub` stores domain data in in-memory repository classes under
`src/repositories/`. There are six of them: `playerRepository.ts`,
`teamRepository.ts`, `parentRepository.ts`, `planRepository.ts`,
`announcementRepository.ts` and `userRepository.ts`. This task documents the two
that have test coverage today, `PlayerRepository` and `TeamRepository`.

Every fact needed to write the document is listed below. Do not read other files
to infer behaviour, and do not describe repositories that are not listed here.

`PlayerRepository` holds a `private readonly store = new Map<string, Player>()`
and exposes four methods:

- `save(player: Player): Player` — writes `{ ...player }` into the map under
  `player.id` and returns a second, separate `{ ...player }`.
- `findById(id: string): Player | undefined` — returns `{ ...player }` when the
  id is present, and `undefined` when it is not.
- `findByTeamId(teamId: string): Player[]` — iterates the map values and returns
  a copy of every player whose `teamId` matches. Returns an empty array when
  nothing matches.
- `delete(id: string): boolean` — delegates to `Map.delete`, so it returns
  `true` when a record was removed and `false` when the id was not present.

`TeamRepository` holds a `private readonly store = new Map<string, Team>()` and
exposes the same four method shapes, plus a private `copyTeam` helper:

- `save(team: Team): Team` — writes `{ ...team, playerIds: [...team.playerIds],
  coachIds: [...team.coachIds] }` into the map and returns `copyTeam(team)`.
- `findById(id: string): Team | undefined` — returns `copyTeam(team)` or
  `undefined`.
- `findByCoachId(coachId: string): Team[]` — returns a copy of every team whose
  `coachIds` array includes the given coach id.
- `delete(id: string): boolean` — same `Map.delete` semantics as above.
- `private copyTeam(team: Team): Team` — returns
  `{ ...team, playerIds: [...team.playerIds], coachIds: [...team.coachIds] }`.

The copy contract that both classes share, and which the tests in
`src/repositories/__tests__/repositories.test.ts` pin, is this: **a caller can
never reach into the store through an object it passed in or an object it got
back.** Both directions matter, and they fail differently:

- The object passed to `save` is copied on the way in, so mutating that object
  afterwards does not change what is stored.
- The object returned by `save` or by a finder is a copy on the way out, so
  mutating it does not change what is stored either.

`TeamRepository` needs more than a spread to honour this, because `Team` carries
the `playerIds` and `coachIds` arrays. A plain `{ ...team }` copies the object
but shares those two array references, which would let a caller push into a
stored roster. That is why both `save` and `copyTeam` rebuild the arrays with
`[...team.playerIds]` and `[...team.coachIds]`. `PlayerRepository` has no array
fields, so a shallow spread is sufficient there.

Both classes hold state only for the lifetime of the process. Nothing is
persisted, and a new instance always starts empty.

TARGET

- Create docs/repositories.md
- Reference src/repositories/playerRepository.ts
- Reference src/repositories/teamRepository.ts

CHANGE

Write `docs/repositories.md` as a reference for a developer who is about to add
a seventh repository class and needs to match the existing conventions.

Structure the document with these sections, in this order:

1. A `# Repositories` title, followed by one short paragraph stating that these
   are in-memory stores keyed by id, holding state only for the process
   lifetime.
2. `## The copy contract` — explain both directions of the contract described in
   CONTEXT, and say why each one matters to a caller.
3. `## PlayerRepository` — a short prose introduction, then a table of the four
   methods with their signatures and what each returns.
4. `## TeamRepository` — the same shape, and a paragraph explaining why the two
   roster arrays are rebuilt rather than spread.
5. `## Adding a repository` — a short checklist covering: copy on the way in,
   copy on the way out, rebuild any array or nested object field, return
   `undefined` rather than throwing when a finder misses, and return a boolean
   from `delete` reflecting whether anything was removed.

Use only the facts in CONTEXT. Do not invent method names, options, persistence
behaviour, or repositories beyond the two documented here.

Output format, which matters as much as the content:

Reply with exactly one block, opened with the line

    ```file path=docs/repositories.md

and closed with a bare triple-backtick line. Write no prose before or after that
block.

Do not open the block with ```markdown or ```md — those are ignored and the task
fails. Do not emit a block for `package.json`, for either reference file, or for
any other path; this task adds no script, no dependency and no configuration, and
every other file in the repository is already correct. If the document itself
needs a fenced example inside it, indent that example by four spaces instead of
fencing it.

ACCEPTANCE

- `docs/repositories.md` exists and is the only file the change adds or edits.
- The document contains all five sections named in CHANGE, with the headings
  written exactly as given.
- Every method signature named in the document appears in CONTEXT.
- No section is left empty, and the document does not end on a heading.
- Fenced code blocks, if any are used, are balanced.
