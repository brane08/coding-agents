# Agent session context and cost discipline

Covers: what drove cost in long Claude Code sessions (cost = turns x context size) and the habits that cut it. Evidence: one review of a ~$43 session (~374M cache-read tokens, ~1.6k main turns, ~80 subagent runs); quality after compaction was not measured.

## Rules
- Do not edit `CLAUDE.md`, settings or tool setup mid-session: it breaks the cached prefix and every later turn pays uncached.
- Keep `CLAUDE.md` small (it is re-read every turn; trimming 22.8 KB to ~11.7 KB moved recipes to on-demand memory files). Put long rules, recipes and runbooks in notes read only when needed.
- Context sat at 200-350k with autocompact ~350k: target a lower threshold (~150-200k). State the measured number before changing a threshold.
- One feature batch per session; `/clear` between batches (state lives in tracking and memory files).
- Idle turns (Stop-hook replies, agent hand-backs, "still waiting") each re-read full context: commit locally as WIP so the hook passes, or avoid ending turns while agents run.
- Filter command output before it reaches context; push bulky reads into subagents with narrow, self-contained prompts that return short summaries. Subagents over ~100k need split prompts.

## Concurrency
- No concurrent Maven on the same module or test DB from subagents: shared `target/` and the shared test schema give bogus boot/FK failures and phantom mass failures, then reruns. Subagents (incl. quick-triage) run one test script at a time, never concurrently; full suite only when preparing the PR.

## Model routing
- Design-heavy items (money, orders, schema) to a stronger model for design and diff review; a cheaper model for mirroring, boilerplate, tracking edits, test/build runs. A cheap model given design work left REST paths uncovered.
