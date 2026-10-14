---
name: delegation-audit
description: Re-run the delegation/model-routing audit over local session transcripts — counts main-thread Bash calls on sonnet/opus that should have gone to haiku agents. Use when asked for a delegation audit, token-discipline review, or "one more pass" on session/agent routing.
---

Run (read-only, no model needed to parse):

```
python3 -I ~/.claude/skills/delegation-audit/audit.py --since YYYY-MM-DD
```

Counts a lookup (Bash, Grep or Glob) as a violation only when it is the 2nd+ in a run with no
Edit/Write/Agent between, is piped/chained, or is an inline module-wide test run; a single
lookup is the allowed locate-before-edit. Prints the run-based count, rate, runs of 3+, a raw
legacy count (old method), per command/project, and top shapes (80 chars, secrets redacted).
Compare the rate against the last entry in `~/.claude/memory/delegation-audit-log.md`; old raw
baselines (408 since 2026-09-23, 808 since 2026-10-07) compare only with the raw line.
Append a 2–3 line entry there; do not paste raw output.

Context/compaction scan (for window or autocompact tuning): `python3 -I ~/.claude/skills/delegation-audit/ctx.py`
(peak context, compactions per session, context at compaction, turns per session; main thread only).
