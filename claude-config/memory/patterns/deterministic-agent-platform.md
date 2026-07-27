# Deterministic meta-agent / catalog-platform patterns

De-identified design lessons from building a credential-free meta-agent platform
(generator role + certify/promotion pipeline over a locked capability catalog).
Reusable across any project that runs LLM-agent generation behind deterministic
tooling. No project/branch/commit/identity specifics — those stay in the repo's
own `.claude/memory/`.

## Seam + deterministic stub (credential-free CI)

- Every place that would call a model or external agent is a **typed callable seam**
  (e.g. `Completer`, `Scorer`, `ToolInvoker`, `Store`, `Harness`). Production wires a
  real backend; tests/CI wire a deterministic stub, so the whole suite runs with **no
  credentials**.
- Backend is selected by env var (e.g. `ORCH_HARNESS`), defaulting to the stub; the
  real backend (`claude-cli` etc.) is opt-in. Unknown backend name → hard error, never
  silent fallback.
- The same seam drives both the conformance fixtures and real dispatch, so stub and
  real backend are interchangeable by construction.

## Stub must not be able to spoof its own gate

- A stub reports **PARTIAL / incomplete, never a false COMPLETE**. If the gate exists
  to catch a lying agent that claims success it never achieved, a stub that claims
  COMPLETE would sail through the very check it feeds. Make the honest stub trip no
  alarm *and* leave the false-COMPLETE detectable.

## Artifacts are the evidence, never the agent's claims

- Verify what was **written to disk**, not what the agent narrated. A generator that
  emits the correct warning and *still* mutated a protected input must fail — prove the
  mutation from a content hash, don't trust the self-report.
- Test conformance suites **in both directions**: a conforming double passes, and one
  cheating double per rule fails. A suite that only ever sees good input proves nothing.

## Publish only on success (atomic, no half-artifacts)

- Generator writes into a scratch dir; on a *completed* run the scratch is **moved**
  into the published location. A crash mid-run leaves no half-candidate for the next
  stage to trip over.
- Promotion is one atomic commit: move + generated manifest + ledger record + trace,
  all together, or nothing.

## Trust/tier ledger: latest-record-per-key, not min()

- Resolve an entry's tier as the **latest record per `(id, version, profile)`**, over an
  append-only ledger — *not* `min()` across all its records. `min()` makes promotion
  (e.g. `quarantined → validated`) impossible: the old low record permanently wins.
- Keep **one** implementation of tier resolution and import it everywhere. Duplicated
  copies drift silently (they had already diverged on profile matching before this was
  caught).
- A **recall/revocation must be distinguishable from "no record"**. Derive a tier only
  when there is genuinely no explicit record; otherwise the explicit record (including a
  recall) wins. Otherwise a recalled item reads as un-recorded and keeps routing.

## Content hashing

- **Length-prefix each field before hashing** file/config content. Without it, embedded
  NUL/boundary bytes can forge field boundaries and collide distinct inputs.

## Deterministic tooling (byte-identical rebuilds)

- Generated lock/output must be **byte-identical for identical input trees** — no
  timestamps, no dict-ordering leaks, LF-normalized. CI builds twice and diffs.

## Role separation as an anti-drift control

- A generator role gets **minimal context** — only its task inputs and capability
  manifest, never the full roadmap/spec/repo. Minimal context is a deliberate anti-drift
  control, not an oversight.
- Keep roles apart across **workspace, permission profile, and injected context**, not
  just by convention in one process. The generator writes only to its candidate dir.

## Conformance is measured, never assumed

- An agent/harness is trusted to "follow the rules" only after a fixture suite measured
  it. Keep the read *and* write of the conformance list in **one module** so the format
  cannot drift, and let it be written **only** by the tool that ran the suite —
  hand-adding an entry asserts conformance nobody measured.
