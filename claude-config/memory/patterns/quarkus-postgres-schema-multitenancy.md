# Pattern: Schema-Per-Tenant Multi-Tenancy (Quarkus + Postgres)

## Problem
A single-tenant Quarkus app (one Agroal pool, one Postgres schema, plain `EntityManager`/JPA)
needs to serve multiple isolated tenants (customers/orgs/schools) without a `tenant_id` column
and `WHERE` filter on every table/query — that touches every entity and every JPQL query and is
easy to get wrong (one missed filter = cross-tenant leak).

## Solution
One Postgres schema per tenant, same tables replicated N times, same Agroal connection pool
shared by all tenants. Hibernate switches `search_path` per request via `Connection.setSchema()`.
Quarkus has first-class built-in support — no custom `MultiTenantConnectionProvider` needed.

## When schema-per-tenant beats row-per-tenant
- Existing single-tenant app being retrofitted (this pattern minimizes touched files)
- Moderate tenant count (tens–low hundreds; each tenant is a real schema + connection overhead,
  not free at thousands of tenants)
- Strong isolation matters (a bug in one query literally cannot see another tenant's rows —
  the row doesn't exist in that connection's search_path, full stop)

Row-per-tenant (shared schema + `tenant_id` column + filter) is more invasive for a retrofit —
prefer it only when starting greenfield with thousands+ tenants where a schema each is unworkable.

## Core config (Quarkus, zero custom Java for the connection-provider side)
```properties
quarkus.hibernate-orm.multitenant=SCHEMA
```
That's it for the datasource side. Quarkus's default `DataSourceTenantConnectionResolver` →
`SchemaTenantConnectionProvider` calls `Connection.setSchema(tenantId)` on **every** connection
checkout from the pool — confirmed by decompiling the provider — so there is no pool-leak risk
from stale schema state on a reused connection. No manual `SET search_path` SQL needed anywhere
in application code.

## The one bean you must write
```java
import io.quarkus.hibernate.orm.runtime.tenant.TenantResolver;

@RequestScoped
public class MyTenantResolver implements TenantResolver {

    @Override
    public String getDefaultTenantId() {
        return "public"; // or your baseline/default schema name
    }

    @Override
    public String resolveTenantId() {
        // MUST come from a server-verified source once authenticated (JWT claim / a
        // request-scoped principal bean populated from that claim) — see Security below.
        // MUST fall back to getDefaultTenantId() when there's no way to resolve tenant,
        // rather than throwing — see Non-HTTP-context gap below.
    }
}
```
On Quarkus 3.38+, add `@PersistenceUnitExtension` to this bean — plain CDI still works but is
deprecated and logs a warning that it "will not work in future versions of Quarkus."

## Gaps that are NOT optional — hit every one of these in production

### 1. Tenant resolution must be tied to a verified identity, not a client-supplied value
The single biggest way this pattern gets broken: reading tenant from a raw header, query param,
or any other client-controlled input with no cryptographic tie to the caller. That lets any
authenticated (or even unauthenticated, pre-fix) caller read another tenant's data just by
changing a value. **Once a request is authenticated, resolve tenant from the JWT's own claim (or
a request-scoped principal populated from that claim) and ignore any client-supplied
header/param entirely** — don't just prefer the claim over the header, stop reading the header
at all post-auth. A raw header is only acceptable pre-auth (see gap 4).

### 2. Validate tenant identifiers against an allow-list before they reach Hibernate/JDBC
`Connection.setSchema()` isn't string-concatenated SQL, so classic SQL injection through the
schema name itself is not the risk — but an unrecognized value still reaches Postgres unvalidated
and comes back as a raw DB error (schema-does-not-exist), not a clean app-level 400. Keep a known-
tenants registry (a table, or even a static config list for small deployments) and reject unknown
values before they hit the persistence layer. This matters more as soon as a tenant id can
originate from more attacker-reachable input than a small set of infra-controlled subdomains.

### 3. `TenantResolver` will be invoked with NO active HTTP request
Any code path that touches the `EntityManager` outside a live JAX-RS request — scheduled
jobs (`@Scheduled`), background workers, test `@BeforeEach`/`@AfterEach` fixtures, async
workflow-engine steps — will still trigger tenant resolution. If your resolver reads
`@Context HttpHeaders` (or anything request-scoped that only exists during an HTTP exchange), it
throws `IllegalStateException: No REST request in progress` for all of these. Wrap request-scoped
lookups in try/catch and fall back to `getDefaultTenantId()`, or design an explicit tenant
argument for background code paths that legitimately need a specific tenant (not the default).

### 4. Login (or any pre-auth request) has no JWT/claim to read tenant from yet
This is a genuine chicken-and-egg problem, not a corner case: the whole point of a login endpoint
is that no verified identity exists yet, so "resolve tenant from the JWT claim" (gap 1) cannot
apply to the login request itself. Something has to identify tenant purely from the transport
layer, pre-authentication:
- Subdomain (`tenant-a.app.example.com`) — standard for SaaS, needs DNS/reverse-proxy support
- URL path/slug (`/tenant-a/login`)
- An explicit tenant field in the login request body (weakest — trusts user input to route their
  own credential lookup, only acceptable if step 2's allow-list plus a subsequent JWT-claim
  cross-check closes the gap)

Use a separate pre-auth-safe request-scoped bean (not your post-auth principal/`CurrentUser`,
which doesn't exist yet at login time) to carry this signal into `TenantResolver`, so login and
authenticated requests share one resolution path instead of two divergent implementations.
Once login succeeds, mint the tenant into the JWT as its own claim so every later request uses
the verified path from gap 1. Optionally cross-check the pre-auth transport signal (subdomain/
path) against the JWT's tenant claim on subsequent requests and reject on mismatch — stops a
token minted for tenant A being replayed against tenant B's URL.

### 5. Flyway needs per-tenant schema targeting, and a hardcoded `search_path` in your migrations will silently defeat it
If any migration file contains a hardcoded `SET search_path TO <schema>;`, it overrides Flyway's
own `-Dflyway.schemas=<newschema>` targeting — you'll get "relation already exists" errors because
Flyway thinks it's provisioning a new schema but the SQL inside keeps writing to the original one.
Fix: template the schema name as a Flyway placeholder (`SET search_path TO ${tenantSchema};` +
`-Dflyway.placeholders.tenantSchema=<value>` per tenant) instead of hardcoding it, and provision
each new tenant's schema by re-running the full migration history with that placeholder bound to
the new schema name.

### 6. A non-Hibernate persistence path (a second datasource, a separate ORM/framework like
MyBatis, a workflow engine with its own connection pool) is NOT covered by
`quarkus.hibernate-orm.multitenant`. That setting only reaches whatever EntityManager/persistence
unit it's attached to. Any parallel datasource needs its own, independently-implemented
tenant-switching mechanism (e.g. an interceptor around that framework's session/connection
acquisition) — don't assume enabling Hibernate SCHEMA multitenancy silently covers the whole app.

### 6a. Workflow/orchestration engines (Copper, Camunda, Flowable, ...) are the sharpest instance of gap 6
These engines almost always run their own persistence underneath the app's ORM — a separate
named datasource, a separate connection pool, often a different data-access framework entirely
(e.g. Copper 6 uses a plain MyBatis `SqlSessionFactory` over Agroal, not Hibernate). Concretely,
for a Copper-shaped engine:
- **The engine's datasource needs its own schema-switching**, independent of the Hibernate
  `TenantResolver` above. Hibernate SCHEMA multitenancy has zero visibility into a MyBatis
  `SqlSessionFactory` or the engine's own connection acquisition path.
- **A running workflow instance is long-lived and asynchronous** — it's created in one HTTP
  request, then resumes later via `wait()`/`notify()` calls, scheduled polling, or engine-internal
  threads with no HTTP request in scope at all (same shape as gap 3, but guaranteed rather than
  occasional). Tenant cannot be re-derived from a JWT/header at resume time because there is no
  inbound request to read one from — **persist the tenant id as a field on the workflow's own
  data object at creation time**, and have every step read it from there, not from ambient
  request context.
- **The engine's own tables (workflow instance state, audit/history, queues) need the same
  schema-per-tenant treatment as domain tables** if you want workflow data isolated per tenant —
  otherwise workflow state for every tenant lands in one shared schema even though domain data is
  split. Decide deliberately whether workflow engine state is per-tenant or intentionally shared/
  global (e.g. a single ops team monitoring all tenants' workflows) — don't let it default to
  shared just because it was easier to wire.
- **`notify()` / external callback endpoints** (a REST action that resumes a waiting workflow)
  need the same tenant-verification treatment as any other authenticated endpoint (gap 1) — plus
  a check that the caller's resolved tenant matches the tenant stored on the workflow instance
  being notified, so a caller can't drive another tenant's workflow forward by guessing/
  enumerating instance IDs.

## Minimum test matrix — workflow engine additions
- A workflow created under tenant A, resumed via `notify()`/callback with no HTTP tenant context
  available (simulating engine-internal resume) → step logic reads tenant from the workflow's own
  data object, not ambient context, and touches only tenant A's schema
- `notify()` called by an authenticated caller resolved to tenant B against a workflow instance ID
  that belongs to tenant A → rejected, not silently processed
- Engine's own persistence (instance/history/queue tables) confirmed to land in the intended
  schema (per-tenant or deliberately shared) — not accidentally shared by default

## Minimum test matrix before shipping
- Cross-tenant header/param override attempt on an authenticated request → must be ignored, not
  honored (regression guard for gap 1)
- Unknown/garbage tenant identifier → must 400 from the app's own allow-list, not a raw DB 500
  (gap 2)
- A scheduled job / background worker / test fixture that touches the EntityManager with no
  active HTTP request → must not throw, must resolve to an explicit or default tenant (gap 3)
- Tampered JWT tenant claim → rejected at signature verification, same as any other claim
- Cross-tenant object-ID probing (a valid ID in tenant A, requested while authenticated as tenant
  B) → must 404, since the row simply doesn't exist in B's search_path — verifies schema
  isolation is actually doing the isolating, not just returning the right totals
- Fresh tenant provisioning via Flyway with the placeholder fix (gap 5) produces a schema with the
  full, current table set — not just whatever the baseline migration alone contains

## Applicable When
- Quarkus + Postgres + Hibernate ORM (plain JPA `EntityManager`, or Panache — same underlying
  mechanism), Agroal connection pooling
- Retrofitting multi-tenancy onto an existing single-schema app, moderate tenant count
- Not tied to any particular domain — this is infra/auth-layer plumbing, independent of what the
  entities actually model
