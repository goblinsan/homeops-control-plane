CONTEXT
project-dashboard already has the dashboard UI route module on main. The
acceptance run should prove the remediated local backend can modify an existing
server registration file, use a reference-only route module for context, add a
focused route test, and pass the repository validation commands without using
premium escalation.

TARGET
- Modify src/routes/ui.ts
- Modify src/server.ts
- Create tests/ui-route.test.ts

CHANGE
Fix any strict TypeScript issues in the existing UI route module, then wire the
UI route registration into the Fastify server if it is not already registered.
Add a focused Vitest route test that builds the server and asserts GET /ui
returns a successful HTML response. Follow the existing route test style in the
repository: import `build` from `../src/server`, create `const app = build()`,
import `beforeAll` and `afterAll` from Vitest, call `await app.ready()` from
`beforeAll`, close the app from `afterAll`, use
`app.inject({ method: "GET", url: "/ui" })` to request the route, and close
the app in cleanup. Do not use `before`, `after`, or `app.request`; those APIs
are not available here. Keep the change scoped to the UI route module, server
registration, and the new UI route test only.

ACCEPTANCE
npm run build passes.
npm test passes.
The implementation does not merge or push directly to main.
