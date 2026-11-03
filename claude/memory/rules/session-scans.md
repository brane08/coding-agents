# Session scans (history reviews, permission audits)

Read before any delegation/permission/context audit.

- Run the scripts, don't hand-parse transcripts: `delegation-audit/audit.py --since <date>`
  (routing) and `delegation-audit/ctx.py` (context/compaction). Main-thread turns only
  (exclude sidechains); dedupe by message id.
- Permission prompts: `delegation-audit/permissions.py --since <date> [--profile both]` →
  report, and new allow/env entries written into repo `settings.<profile>.json` from the
  `log-ask.sh` log (`--dry-run` to preview); never add rules from memory of a prompt.
- Always report: window checked (dates, session count, per project); routing violation rate vs
  the last log entry; peak context + context at compaction + compactions per session + turns
  between compactions; turns/tokens per model (main vs subagents) with the share of
  mechanical-only turns (Bash/Grep/Glob/Read, no text) per model, and what could drop a tier
  (sonnet/opus subagent doing lookups → haiku; opus outside auth/crypto/concurrency/migration
  → sonnet); top 3 repeated shapes; which rules/hooks were changed since the last scan (so a
  rate change is attributable). Flag sessions open before the last config change.
- Before changing a window/autocompact/hook setting, state the measured number it targets.
  Log 2–3 lines in `~/.claude/memory/delegation-audit-log.md`; never paste raw output.
- Cost claims: separate cache-read from uncached tokens; say what was not measured (quality
  after compaction).
