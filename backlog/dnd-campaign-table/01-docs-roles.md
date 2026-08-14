# Document the role and permission model in docs/roles.md

CONTEXT

`dnd-campaign-table` gates every view through a role capability matrix in
`src/roles.ts`. The matrix is the whole authorisation model, and it is
undocumented, so anyone adding a screen has to read the source to learn which
role may see what.

Every fact needed is listed here. Do not read other files to infer behaviour and
do not invent roles or permissions beyond this list.

There are three roles, exported as `ROLES`:

- `dm` — the Dungeon Master. Full access, including hidden content.
- `player` — a player character's owner. Own-character data plus the visible
  game world.
- `table` — the shared group display. Public-only campaign content.

Permissions are grouped by the thing they govern:

- `session:create`, `session:read`, `session:manage`
- `character:read:own`, `character:read:all`, `character:write`
- `encounter:read:public`, `encounter:read:full`, `encounter:manage`
- `npc:read:visible`, `npc:read:full`, `npc:manage`
- `notes:read:dm`, `notes:write:dm`
- `map:read:visible`, `map:read:full`, `map:manage`

`CAPABILITIES` maps each role to the set of permissions it holds.

`dm` holds every permission in the list above — all seventeen.

`player` holds exactly six: `session:read`, `character:read:own`,
`character:write`, `encounter:read:public`, `npc:read:visible`,
`map:read:visible`.

`table` holds exactly four: `session:read`, `encounter:read:public`,
`npc:read:visible`, `map:read:visible`.

So `table` is `player` minus the two character permissions. The difference
between the two is that a table display is a shared screen with no owner, so it
must never show a character sheet, while a player owns exactly one.

The `:own`, `:visible`, `:public` and `:full` suffixes carry the design. A role
holding `encounter:read:public` sees only what the DM has revealed; only
`encounter:read:full` sees hidden detail. The same split applies to NPCs
(`npc:read:visible` against `npc:read:full`) and the map (`map:read:visible`
against `map:read:full`). The DM-private notes have no public counterpart at
all: `notes:read:dm` and `notes:write:dm` are held by `dm` alone.

`hasPermission(role, permission)` is the only read path. It returns `false` when
either argument is missing, looks the role up in `CAPABILITIES`, and returns
`false` for an unknown role rather than throwing. It is deny-by-default: a
permission absent from a role's set is denied, and a typo in a permission name
denies rather than grants.

`CAPABILITIES` and `ROLES` are both frozen with `Object.freeze`, so the matrix
cannot be edited at runtime.

TARGET

- Create docs/roles.md
- Reference src/roles.ts

CHANGE

Write `docs/roles.md` for a developer about to add a screen or endpoint that
must be permission-gated.

Structure the document with these sections, in this order:

1. A `# Roles and permissions` title, then one short paragraph stating that
   `src/roles.ts` holds the whole authorisation model and that it is
   deny-by-default.
2. `## The three roles` — a table of the three roles with what each represents.
3. `## Permissions` — the permission names grouped by the thing they govern, and
   an explanation of what the `:own`, `:visible`, `:public` and `:full` suffixes
   mean.
4. `## Who holds what` — a table with one row per permission and one column per
   role, marking which roles hold it. State that `dm` holds all seventeen.
5. `## Checking a permission` — describe `hasPermission`, including that it
   returns `false` for a missing argument or an unknown role rather than
   throwing, and why that makes a typo fail closed.

Use only the facts in CONTEXT. Do not invent roles, permissions, or functions.

Output format, which matters as much as the content:

Reply with exactly one block, opened with the line

    ```file path=docs/roles.md

and closed with a bare triple-backtick line. Write no prose before or after that
block.

Do not open the block with ```markdown or ```md — those are ignored and the task
fails. Do not emit a block for `package.json`, for the reference file, or for any
other path; this task adds no script, no dependency and no configuration, and
every other file in the repository is already correct.

ACCEPTANCE

- `docs/roles.md` exists and is the only file the change adds or edits.
- The document contains all five sections named in CHANGE, with the headings
  written exactly as given.
- The `Who holds what` table lists every one of the seventeen permissions.
- `player` is shown with exactly six permissions and `table` with exactly four.
- No section is left empty, and the document does not end on a heading.
