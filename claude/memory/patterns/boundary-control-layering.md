# Per-feature boundary/control package layering

De-identified pattern for organizing a Quarkus (or similar) monolith's web
layer by feature, with a shallow ECB-style (Entity-Control-Boundary) split
inside each feature package — not a project-wide architecture, just the web
module's convention.

## The split

Per feature, use up to three sibling packages under the feature name:

| Package | Contains | Naming suffix |
|---------|----------|----------------|
| `<feature>.boundary` | HTTP-facing classes: REST resources, HTMX/MVC controllers, exception mappers, auth filters/mechanisms, template-global helpers | `*Controller`, `*Resource`, `*ExceptionMapper`, `*Filter`, `*Mechanism` |
| `<feature>.control` | Business logic that isn't a data-access concern: services, scheduled jobs | `*Service`, `*Job` |
| `<feature>.entity` | Request/session-scoped context beans (not persistence entities — those live in the data module) | plain noun, e.g. `CurrentUser` |

Data-access layers (entities, repositories, mappers) live in a **separate**
module/package tree entirely (`.entities`, `.repositories`, `.mappers`) — the
web module's `.entity` package is for transient request context, not JPA
entities. Don't conflate the two "entity" meanings.

## Apply it selectively, not dogmatically

- Simple CRUD-only features (pure UI passthrough, no business logic beyond
  the repository call) get `.boundary` only — no empty `.control` package
  just to satisfy the pattern.
- Cross-cutting concerns (auth, session, global error handling) get their
  own pseudo-feature package (e.g. `session.boundary`) rather than being
  smeared across every real feature.
- Scheduled/background jobs are `.control` even when they have no
  corresponding `.boundary` counterpart (no HTTP entry point) — group all
  jobs under one `scheduler.control` package rather than scattering them
  per-feature if they don't map cleanly to a single feature.
- A module implementing a different concern entirely (a workflow engine, an
  LLM agent service) is not forced into this shape — it uses whatever
  package layout fits that concern (e.g. `.defs`/`.infra`/`.spi` for a
  workflow engine). Don't cargo-cult the web module's convention onto
  modules that aren't structured as HTTP-facing features.

## Why this is worth keeping

- Grepping `*.boundary` finds every HTTP entry point in the app in one shot
  — useful for security review (auth checks), API surface audits, and
  exception-mapper completeness checks (every `WebApplicationException`
  subtype thrown from a `.boundary` class should have a matching mapper).
- Grepping `*.control` finds every piece of business logic that isn't
  straight data access — useful for finding where a given side effect
  (notification, state transition) actually happens.
- The suffix convention means you can often guess a class's location and
  role from its name alone, without reading the code.
