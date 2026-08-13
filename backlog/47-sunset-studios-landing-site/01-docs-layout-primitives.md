# Document the three layout primitives in docs/layout-primitives.md

CONTEXT

`47-sunset-studios-landing-site` is a Next.js app. Every page is composed from
three layout primitives in `src/components/layout/`, re-exported together from
`src/components/layout/index.ts`. They are undocumented, so a contributor adding
a page has to read the source to learn the nesting order.

Every fact needed is listed here. Do not read other files to infer behaviour and
do not document components that are not listed here.

All three call the `cn` helper from `@/lib/utils` to merge an optional
`className` prop over their own classes, so a caller can always override styling
without forking the component.

`PageContainer` — props `children: React.ReactNode` and `className?: string`.
It renders a `div` carrying `bg-surface-0 text-text-primary min-h-screen`, which
is what enforces the dark brand background and global text colour. Inside it
renders a skip-to-content anchor pointing at `#main-content`, styled `sr-only`
so it is invisible until focused, then a `<main id="main-content" tabIndex={-1}>`
wrapping the children. The `tabIndex={-1}` exists so the skip link can move focus
into `main` programmatically without putting `main` itself into the tab order —
that is the correct skip-link pattern. Every page is wrapped in this.

`Section` — props `children: React.ReactNode`, `className?: string`,
`id?: string`, `'aria-labelledby'?: string`, and `animate?: boolean` which
defaults to `false`. It renders a `<section>` with
`py-section sm:py-section-lg px-4 sm:px-6`, which is what gives every section the
same vertical rhythm. When `animate` is true it adds `animate-fade-up`, a token
defined in `globals.css`, so the section fades and rises on mount. Remaining
props are spread onto the element, which is how `aria-labelledby` reaches the
DOM; pass it the id of the section's heading so screen readers announce the
section by name.

`ContentArea` — props `children: React.ReactNode`, `className?: string`, and
`size?: ContentAreaSize` which defaults to `'xl'`. `ContentAreaSize` is the union
`'sm' | 'md' | 'lg' | 'xl' | 'full'`. It renders a `div` with `mx-auto w-full`
plus one max-width class chosen from this map:

- `sm` maps to `max-w-lg`, 512 px
- `md` maps to `max-w-2xl`, 672 px
- `lg` maps to `max-w-4xl`, 896 px
- `xl` maps to `max-w-6xl`, 1152 px
- `full` maps to `max-w-full`, unconstrained

Because every section's content passes through the same map, all sections stay
aligned to one horizontal grid.

The intended nesting order is `PageContainer` outermost, then one `Section` per
band of the page, then a `ContentArea` inside each section to constrain its
width. `PageContainer` supplies the page chrome, `Section` supplies vertical
spacing, `ContentArea` supplies horizontal constraint; none of them duplicates
another's job.

TARGET

- Create docs/layout-primitives.md
- Reference src/components/layout/ContentArea.tsx

CHANGE

Write `docs/layout-primitives.md` for a contributor about to add a new page.

Structure the document with these sections, in this order:

1. A `# Layout primitives` title, then one short paragraph naming the three
   components and stating that they are re-exported from
   `src/components/layout/index.ts`.
2. `## Nesting order` — describe the intended nesting and what each of the three
   contributes, as stated in CONTEXT.
3. `## PageContainer` — its props and what it renders, including why the skip
   link and `tabIndex={-1}` are there.
4. `## Section` — its props, the vertical rhythm classes, what `animate` does,
   and how `aria-labelledby` should be used.
5. `## ContentArea` — its props, and a table of the five `size` values with the
   max-width class and pixel width each one maps to.

Use only the facts in CONTEXT. Do not invent props, components, or styling
tokens.

Output format, which matters as much as the content:

Reply with exactly one block, opened with the line

    ```file path=docs/layout-primitives.md

and closed with a bare triple-backtick line. Write no prose before or after that
block.

Do not open the block with ```markdown or ```md — those are ignored and the task
fails. Do not emit a block for `package.json`, for the reference file, or for any
other path; this task adds no script, no dependency and no configuration, and
every other file in the repository is already correct. If the document needs a
fenced example inside it, indent that example by four spaces instead of fencing
it.

ACCEPTANCE

- `docs/layout-primitives.md` exists and is the only file the change adds or
  edits.
- The document contains all five sections named in CHANGE, with the headings
  written exactly as given.
- The `ContentArea` table lists all five size values.
- No section is left empty, and the document does not end on a heading.
- Every prop named in the document appears in CONTEXT.
