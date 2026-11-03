# ShedLock with Quarkus `@Scheduled` (Quarkus 3.40, grocery-shop and academy usage)

Covers: running each scheduled job on one node when the app is replicated, annotation rules, duration format, test-flag caveat. Table `shedlock`. Not verified against ShedLock release notes; facts come from project conventions.

## Rules
- Every `@Scheduled` method carries `@SchedulerLock(name, lockAtMostFor, lockAtLeastFor)`, applied through a project `SchedulerLockInterceptor` (CDI interceptor around the ShedLock lock provider). A new scheduled job = a new annotation with a unique `name`.
- Durations are ISO-8601 strings (`PT30S`, `PT5M`).
- `lockAtMostFor` must exceed the worst-case runtime (else a second node can start while the first still runs).
- For `every=` triggers set `lockAtLeastFor` just under the interval (so a fast run cannot re-fire on another node within the same tick).
- Exception: per-pod jobs (in-memory config refresh, `SKIP` concurrency, no lock) must run on every replica; leave them without `@SchedulerLock`. Idempotent / `SKIP LOCKED` jobs need no lock either.
- Variant without annotation: a helper `SchedulerLock.runExclusively(name, atMostFor, atLeastFor, task)` wrapping the task, same table.

## Tests
- Disable the at-least window in tests via a config flag (e.g. `<app>.scheduler.lock.at-least-for-enabled=false`) so repeated runs are not suppressed.
- Never `DELETE` from `shedlock` in tests: ShedLock caches row existence and then fails to re-insert. Expire the lock instead (`UPDATE shedlock SET lock_until = ...` in the past).

## Spring port
- Replace the interceptor with `shedlock-spring` `@SchedulerLock`; recheck ISO-duration handling and the at-least-for test flag.
