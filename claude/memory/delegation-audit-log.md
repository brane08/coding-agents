# Delegation audit log

Tracks resolved findings from session-history delegation/model-routing audits so
future audits don't re-flag the same already-fixed gaps.

## 2026-09-23
- Audited local session history for haiku-delegable work run inline on sonnet/opus
  (per CLAUDE.md `## Delegation (token discipline)`). Found 1,753 violations across
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

## 2026-10-07
- Re-audit (6 transcripts since 2026-09-23): 408 violations vs 1,753 baseline (-77%).
  tail 85→3, head 12→2, ls 30→10; cat rose 58→80. Remaining: grep (142), sed (106),
  git diff/log/show (14), mostly academy and grocery-shop.
- Rule text now allows a single `grep`/`cat` on one known path inline; 2+ chained → `code-search`.

## 2026-10-14
- Opus review of 17 transcripts since 2026-10-07: raw 808 was ~40% false positives and volume-driven
  (reminders fired ~340×/day with no effect; only a deny changes behaviour). audit.py now counts
  runs (2nd+ lookup, no Edit/Write/Agent between), piped/chained lookups, Grep/Glob tools and
  inline test runs, and prints a rate. New baseline: 450 violations / 1,749 calls (26%), 89 runs of 3+
  (raw legacy 842). Old raw baselines compare only with the raw line.
- Fixes: nudge-delegate.sh denies piped/chained lookups; CLAUDE.md locate-before-edit rule;
  `pr-squash-sync/sync-check.sh`; test.sh failure details; code-search returns line ranges;
  admin-only `hooks/chain-guard.sh` denies the 3rd consecutive lookup. Re-audit after a restart:
  sessions open before these changes ran the old rules.

## 2026-10-17
- `hooks/chain-guard.sh` limit 3 -> 7 consecutive lookups (user choice). Target number not measured: no count of
  `chain-deny` rows in `state/delegation-nudges.tsv` beforehand. Re-audit with `audit.py` and compare.
- `~/.claude` added to `additionalDirectories`; ask-log scan (21 asks) showed Bash `grep` on `~/.claude` as the
  repeat prompt, 0 `Grep`-tool asks. Detail: `memory/sessions/2026-10-17-config-sync-and-permissions.md`.

## 2026-10-18
- Subagent windows: added `autoCompactWindow: 110000` (frontmatter, needs Claude Code v2.1.296+)
  to all 9 `agents/*.md`. Not measured: no `ctx.py` peak-context-per-subagent number was available
  (transcripts are on the local machine); chosen by hand as a cap well below the session's 400000.
  Re-run `ctx.py`; if no subagent ever nears 110k the field is inert, if some compact often raise it.
- Scan 2026-10-16..18 (16 transcripts, 600 lookups): 61 violation runs = 10% (raw legacy 106); grocery-shop 6, academy 39,
  coding-agents 16. Not compared with the 2026-10-14 baseline (26%, different counting window). No rule/hook changes since 10-17.
- `ctx.py` is all-time, all projects (24 sessions, 56 compactions): peak median 156k, p90 341k; compaction median 157k. Sonnet main
  cache-read ~97% of input (630M vs 18.2M fresh), so main-thread context size is the cost driver. Subagents: sonnet 4972 turns
  (32% mechanical, 32M fresh), haiku 3308 (19%, ~5.9k fresh/turn), opus 1044 (26%).
- Targets, no setting changed: main window cap ~200k, long implementer runs split one bug per agent, lookups to haiku. Not measured:
  this session alone, dollar cost, quality after compaction.

## 2026-10-21
- Main `autoCompactWindow` 400000 -> 350000 and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 90 -> 85 (user choice, both profiles). Targets the 10-18
  `ctx.py` numbers: peak p90 341k (window sits just above it), compaction median 157k. If trigger = pct x window: ~297k vs ~360k before.
  Looser than the 10-18 ~200k cap target. Not measured: sessions that reach 297k, quality after compaction. Re-run `ctx.py` to compare.
