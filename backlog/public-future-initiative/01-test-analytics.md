# Cover lib/analytics.ts with tests in __tests__/lib/analytics.test.ts

CONTEXT

`public-future-initiative` tracks conversion events through `trackEvent` in
`lib/analytics.ts`. It is the only path by which a signup, a form submit or a
pilot click is recorded, and it has no tests. Its sibling modules `content.ts`,
`metadata.ts` and `validate-content.ts` each have a test file under
`__tests__/lib/`; this one does not.

Every fact below was verified by running against this repository's own jest
setup. Do not read other files to infer behaviour.

Test environment facts:

- `jest.config.js` sets `testEnvironment: 'jsdom'`, so `window` is always
  defined inside a test. There is no need to guard for it.
- `process.env.NODE_ENV` is `'test'` inside a jest run, not `'production'`.
- Existing tests live in `__tests__/lib/` and import the module under test with a
  relative path such as `../../lib/analytics`.

`trackEvent(event)` takes one argument, an `AnalyticsEvent`, which is an object
with a `name` and an optional `props`. It returns `void`. Its behaviour, in the
order the function checks:

1. If `window` is undefined it returns immediately. This is the server-side
   no-op. **Do not write a test for this branch** — the jsdom environment always
   defines `window`, so it is not reachable from this file.
2. If `window.plausible` is a function, it calls
   `window.plausible(event.name, { props: event.props })` when `event.props` is
   present, and `window.plausible(event.name, undefined)` when it is absent —
   that is, the second argument is literally `undefined`, not an empty object.
   It then returns, so nothing is logged.
3. Otherwise, if `process.env.NODE_ENV !== 'production'`, it calls
   `console.info('[analytics]', event.name, event.props ?? {})` — three
   arguments, with an empty object substituted when `props` is absent.
4. Otherwise it does nothing at all.

Valid event names, for use in tests: `newsletter_signup`,
`volunteer_form_submit`, `partner_inquiry_submit`,
`local_organizer_form_submit`, `pilot_submission_submit`,
`contact_form_submit`, `event_registration_click`, `pilot_signup_click`.

`newsletter_signup` takes `props` of `{ location?: string }`.
`contact_form_submit` takes `{ type?: string }`. `pilot_signup_click` takes
`{ pilotSlug?: string; pilotTitle?: string }`. The rest take
`Record<string, string>`.

TARGET

- Create __tests__/lib/analytics.test.ts
- Reference lib/analytics.ts

CHANGE

Write `__tests__/lib/analytics.test.ts` covering the three reachable branches.

Use a `beforeEach` that deletes `window.plausible` so each test starts from a
known state, and restore any spy you create.

Write exactly these six tests:

1. Forwards to `window.plausible` with the props wrapper. Assign a
   `jest.fn()` to `window.plausible`, call
   `trackEvent({ name: 'newsletter_signup', props: { location: 'footer' } })`,
   and assert the mock was called once with
   `('newsletter_signup', { props: { location: 'footer' } })`.
2. Passes `undefined` as the second argument when the event has no props.
   Call `trackEvent({ name: 'contact_form_submit' })` and assert the mock was
   called with `('contact_form_submit', undefined)`.
3. Does not also log when plausible handled the event. With `window.plausible`
   assigned and a `jest.spyOn(console, 'info')` in place, call `trackEvent` once
   and assert `console.info` was not called.
4. Falls back to `console.info` when plausible is absent. With no
   `window.plausible`, spy on `console.info`, call
   `trackEvent({ name: 'pilot_signup_click', props: { pilotSlug: 'x' } })`, and
   assert it was called with `('[analytics]', 'pilot_signup_click', { pilotSlug: 'x' })`.
5. Substitutes an empty object in the fallback when props are absent. Call
   `trackEvent({ name: 'contact_form_submit' })` with no plausible and assert
   `console.info` was called with `('[analytics]', 'contact_form_submit', {})`.
6. Stays silent in production. Save `process.env.NODE_ENV`, set it to
   `'production'`, call `trackEvent` with no plausible assigned, assert
   `console.info` was not called, and restore the original value afterwards so
   the change cannot leak into another test.

Every assertion must check a specific value. Do not write an assertion that
would pass whatever the function did.

Output format, which matters as much as the content:

Reply with exactly one block, opened with the line

    ```file path=__tests__/lib/analytics.test.ts

and closed with a bare triple-backtick line. Write no prose before or after that
block.

Do not open the block with ```ts or ```typescript — those are ignored and the
task fails. Do not emit a block for `package.json`, for the reference file, or
for any other path; this task adds no script, no dependency and no
configuration.

ACCEPTANCE

- `__tests__/lib/analytics.test.ts` exists and is the only file the change adds
  or edits.
- It contains six tests matching the six described in CHANGE.
- Every test asserts a specific argument list or a specific not-called
  condition; none asserts something trivially true.
- The production test restores `process.env.NODE_ENV` to its original value.
- No test is written for the server-side `window === undefined` branch.
- `npm test` passes.
