---
name: delegation-audit
description: Re-run the delegation/model-routing audit over local session transcripts — counts main-thread Bash calls on sonnet/opus that should have gone to haiku agents. Use when asked for a delegation audit, token-discipline review, or "one more pass" on session/agent routing.
---

Run (read-only, no model needed to parse):

```
python3 -I ~/.claude/skills/delegation-audit/audit.py --since YYYY-MM-DD
```

Prints counts per command category and per project, plus top command shapes (first 80 chars,
secrets redacted). Counts are an upper bound: it can't tell whether a `cat`/`sed` target was
created that turn. Compare against the last entry in `memory/delegation-audit-log.md`
(baseline 2026-10-07: 408 since 2026-09-23). Append a 2–3 line entry there; do not paste raw output.
