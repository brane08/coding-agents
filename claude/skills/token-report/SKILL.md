---
name: token-report
description: >
  Use when asked how many tokens were used, for a token-usage or cache-read report, or to compare model usage (Fable/Opus/Sonnet/Haiku) across local sessions and subagents. Read-only; summarises ~/.claude/projects transcripts.
disable-model-invocation: true
---
# Token report

Run: bash ~/.claude/skills/token-report/report.sh
One project (name substring): bash ~/.claude/skills/token-report/report.sh grocery

Prints two tables (main sessions, subagent transcripts) with sessions, messages, input, output, cache_read, cache_create and cache_read per message, one row per model plus a TOTAL.

- Counts are tokens, not cost. Cache reads are context length × turns, so they dominate; output is the smaller number.
- Large transcript sets take a few minutes; run it through `quick-triage` rather than in the main thread.
- Never Read the `.jsonl` transcripts directly (huge).
