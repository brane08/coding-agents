# Delegation audit log

Tracks resolved findings from session-history delegation/model-routing audits so
future audits don't re-flag the same already-fixed gaps.

## 2026-09-23
- Audited local session history for haiku-delegable work run inline on sonnet/opus
  (per CLAUDE.md `## Delegation` / `## Model routing`). Found 1,753 violations across
  8 local projects; worst offenders grocery-shop, academy, oauth2-samples (~100%
  sonnet, 0% delegation). Breakdown of read-only command violations: tail (85),
  cat (58), ls (30), head (12) — not explicitly covered by the CLAUDE.md rule text
  or `hooks/nudge-delegate.sh` at the time.
- Verified `hooks/nudge-delegate.sh` already matches `cat|ls|tail|head|wc|sed|awk|
  grep|rg|find|tree|fd` in its case statement — no hook edit was needed; confirmed
  live via synthetic `tail`/`cat` stdin payloads, both fire the nudge correctly.
- Updated `~/.claude/CLAUDE.md` delegation rule text to explicitly name
  `cat`/`ls`/`tail`/`head`/`wc`/`sed`/`awk` so the documented rule matches what the
  hook already enforces. **Resolved — no further action needed on this gap.**
