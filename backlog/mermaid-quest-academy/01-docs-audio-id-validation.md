# Document the AudioId grammar and its two validators in docs/audio-id-validation.md

CONTEXT

`mermaid-quest-academy` names every audio clip with an `AudioId` string. The
grammar is enforced by `src/utils/audioIdValidator.ts` against constants in
`src/types/audioId.ts`. There is authoring guidance in
`src/docs/AUDIO_ID_AUTHORING.md`, but the validation rules themselves are not
written down in one place.

Every fact needed is listed here. Do not read other files to infer behaviour and
do not invent categories, functions or error messages.

An AudioId is a dot-separated string. It is valid when all three hold:

1. It is a non-empty string.
2. It has between two and four dot-separated segments, and each segment starts
   with a lowercase letter and then contains only lowercase letters, digits and
   underscores. The whole-string pattern is
   `/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){1,3}$/` and the single-segment pattern
   is `/^[a-z][a-z0-9_]*$/`.
3. Its first segment is one of seven reserved categories, in this order:
   `phoneme`, `word`, `prompt`, `feedback`, `reward`, `ui`, `narration`.

Valid examples: `phoneme.letter.s`, `word.cvc.sat`, `feedback.correct`,
`prompt.echo_song.default`, `reward.level_complete`.

Invalid examples and why: `""` is empty; `Phoneme.letter.s` has an uppercase
letter; `unknown.thing` uses a category that is not reserved;
`phoneme.letter.s.x.y` has five segments, one more than the maximum.

There are two functions, and they exist for different callers.

`isValidAudioId(id: string): id is AudioId` returns a boolean and is a
TypeScript type guard, so a `string` narrows to `AudioId` inside the `if`. It is
written for hot paths: it runs one regex test, finds the first dot with
`indexOf` rather than splitting the string, and does one `Set` lookup for the
category. No intermediate arrays are allocated.

`validateAudioId(id: string): AudioIdValidationResult` returns
`{ valid: true }` or `{ valid: false, error: string }`, where `error` is
`undefined` when valid. It repeats the whole-string test, then splits the id and
tests each segment individually so it can name the offending segment, then
checks the category. Its three failure messages are, in the order they are
reached: the id is not a non-empty string; the id does not match the
whole-string pattern; a single segment does not match the segment pattern; and
the category is not reserved, listing the reserved ones.

The division: use `isValidAudioId` when a boolean is enough or when you want the
type narrowing, and `validateAudioId` when a human or an author needs to be told
what is wrong. `validateAudioId` costs a string split and does more work, which
is why the fast path does not use it.

TARGET

- Create docs/audio-id-validation.md
- Reference src/utils/audioIdValidator.ts

CHANGE

Write `docs/audio-id-validation.md` for a contributor adding new audio content
or calling the validators from new code.

Structure the document with these sections, in this order:

1. A `# AudioId validation` title, then one short paragraph stating what an
   AudioId is and that the grammar is enforced in code.
2. `## The grammar` — the three rules from CONTEXT, including both regular
   expressions and the segment count range.
3. `## Reserved categories` — the seven categories as a list, in the order given.
4. `## Examples` — a table of the valid examples, then a table of the invalid
   ones with the reason each is rejected.
5. `## Which function to call` — describe both functions, their return types,
   that `isValidAudioId` is a type guard, and when to prefer each.

Use only the facts in CONTEXT. Do not invent categories, functions or error text.

Output format, which matters as much as the content:

Reply with exactly one block, opened with the line

    ```file path=docs/audio-id-validation.md

and closed with a bare triple-backtick line. Write no prose before or after that
block.

Do not open the block with ```markdown or ```md — those are ignored and the task
fails. Do not emit a block for `package.json`, for the reference file, or for any
other path; this task adds no script, no dependency and no configuration, and
every other file in the repository is already correct.

ACCEPTANCE

- `docs/audio-id-validation.md` exists and is the only file the change adds or
  edits.
- The document contains all five sections named in CHANGE, with the headings
  written exactly as given.
- All seven reserved categories are listed, in the order given in CONTEXT.
- Both function names appear with their return types.
- No section is left empty, and the document does not end on a heading.
