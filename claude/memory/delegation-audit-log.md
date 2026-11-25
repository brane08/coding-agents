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

## 2026-10-28 (permission prompts)
- `permissions.py --since 2026-10-24 --profile both --dry-run` (separate haiku agent): 150 dialogs, 0 classifier denials, 38 groups. Top: `javap` 37 and
  `Write(*.md)` 12 (allowed yet prompted, so a hook asks; no rule fixes it), `psql` 12, `git branch -D` 8, `git push --force-with-lease` 4, `unzip` 12.
- Dry run proposes per profile: allow `Bash(unzip *)`, allow `Bash(npx ui-angular *)`, env `OPENROUTER_API_KEY`. Nothing written; kept as prompts: psql writes,
  force-push, branch -D, dependency installs, shell `-c` wrappers. Not measured: which hook asks for javap/Write(*.md).
- Re-run same day, `--since 2026-10-24 --dry-run`, all projects (grocery-shop, pagila-samples, academy): 205 dialogs (+55), 0 classifier denials, 47 groups.
  Subagent-origin prompts dominate: javap 38/38, `git grep` 13/13, outside-cwd `grep`/`ls`/`find` 32 of 32 (~/.m2 sources jars, ms-playwright cache).
  New vs earlier run: `git grep *` (13, no rule) and `gh pr create *` (4; 2 compound via `$()`, 2 no rule). Dry run now proposes 5 allows + 1 env per
  profile (`git grep *`, `unzip *`, `genai-assistant/.venv/bin/python *`, `npx ui-angular *`, `gh pr create *`; `OPENROUTER_API_KEY`). Nothing written.
  Open decisions: (1) ~/.m2/repository as additionalDirectories (removes ~32 prompts from "prefer maven sources" work, but widens acceptEdits edits; secrets deny
  rules stay), (2) find the hook behind javap/unzip -l/Write(*.md) asks (not measured), (3) the `OPENROUTER_API_KEY` env prefix is a secret in a command line:
  move to env, don't allow the prefix. Kept as prompts: psql writes, `git branch -D` (9), force-push (8), `uv pip install` (5), `-c` wrappers (2).
  Report: ~/.claude/state/permission-analysis/permission-report.md.
- 2026-10-28 re-run `--since 2026-10-24 --profile both --dry-run`: 206 dialogs, 47 groups, 0 classifier denials. Top: javap 38, git grep 13, psql 12, Write(*.md) 12, grep 12 (outside cwd), unzip 11+6, ls 10, find 10+5. Proposals unchanged (5 allow + OPENROUTER_API_KEY env). Recurred: javap, unzip, npx ui-angular, OPENROUTER env. No settings changed.

## 2026-11-03 (permission prompts, applied)
- Same window, same 206 events / 47 groups (ask log unchanged since 10-28). Applied: 5 allows + 1 env per profile. Added by hand to both profiles: allow `rg *`, `uniq *`;
  deny `find -fprint`, `sort -uo`, `cat f > out`, `.env` head/tail/cat -n/grep forms, `grep -R /abs`; chain-guard hook wired in sandbox (grocery-shop/academy memory audits).
  `jar-inspect` + CLAUDE.md now prefer source over javap. Not measured: effect on javap prompt count (re-run `permissions.py` after a week).
- Main `autoCompactWindow` 350000 -> 250000 and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` 85 -> 80 (user choice, all 4 settings files). Targets the 10-18 `ctx.py` numbers
  (peak p90 341k, compaction median 157k): trigger pct x window = ~200k vs ~297k, matching the earlier ~200k cap target. Not measured: quality after compaction,
  how often autonomous loops now compact. Re-run `ctx.py` to compare.

## 2026-11-18
- `audit.py --since 2026-11-03` (29 transcripts): 318 violations / 1,625 calls = 20% (vs 26% on 10-14, 10% on 10-18 window; windows differ), 79 runs of 3+, raw legacy 604.
  grep 241 (grocery-shop 188 of 318 total), test-run 35 (`uv run pytest -q` 13, `test.sh htmx-quarkus` 6 inline), git-diff 10, rest <10 each.
- `ctx.py` (22 sessions, all-time): peak median 184k, p90 428k, max 541k; 21 compactions in 6 sessions, compaction ctx 174-184k (matches 250k x 80% ~200k trigger).
  Top-8 peaks (academy 541k, grocery-shop 506k, disk-analyzer-fx 428k) show 0 compactions: sessions run past the cap. Main sonnet cache-read 485M. No settings changed.
- `permissions.py --since 2026-11-03` (report only): 238 events, 71 groups, 1 classifier denial (mvn-test.sh). Top: `git push *` 52 (allowed yet prompted, a hook asks),
  subagent `cd * + …` compounds 25, `env *` 12, outside-cwd `grep` 12 (academy-wt worktrees) + `cat` 6, `jq -n -f /tmp/...` path-form 12, `git log *` 12 / `find *` 11 allowed yet prompted,
  `git checkout *` ask-override 8, scratchpad `python3 /tmp/...` 5. Dry run proposes 0 allow, 1 env. Open: find the hook asking on push/log/find; `academy-wt` as additionalDirectories?
- grocery-shop grep shapes (code-search, 4 transcripts since 2026-11-03, hand tallies so approximate): 327 main-thread greps, 32 runs of 3+ holding 110 (~34%), longest 5.
  Targets: Java main ~45%, `.claude/memory/tracking/*` ~28% (bugs.md, findings/design.md), Java tests ~15%, logs/tool-output ~8%, SQL/config ~4% each. ~90 use the absolute repo path.
  Top shapes: BG-id lookups in tracking ~35, symbol alternation over htmx-quarkus/src/main ~30, single-file member lookups ~25, test-output triage `grep "Tests run:|BUILD|FAIL"` ~25,
  `grep -rln` test discovery ~20. Suggested, not applied: Grep tool for repo-wide symbol searches; batch multi-symbol and tracking lookups into one `code-search`; test triage via `test.sh`/`quick-triage`.
- Resolved (11-18): `academy-wt` was an assistant-created sibling worktree dir (academy session 5c4e8970, 2026-11-16 22:24Z), moved to `academy/.claude/worktrees/set-{a..d}` 3 min later;
  stale subagent paths caused the outside-cwd prompts. No additionalDirectories change; rule added to `rules/conventions-detail.md` (worktrees under `<repo>/.claude/worktrees/`).
  The `git push` (52, main, mode auto), `git log @{u}` (12) and `find` group (12) prompts are not hook-driven (no hook emits ask with jq present); added `@{u}`/find-group avoidance to `agents/code-search.md`,
  no-`cd` line to flyway-next/stack-check/workflow-check agents.

## 2026-11-21
- Why no compaction in the 11-18 top-peak sessions: commit 65073b7 dropped `autoCompactWindow`, and models have a 1M window (docs), so the 80% override alone triggers at ~800k.
  Peaks of 428-541k never reached it. Fix (user choice): `CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000` in `~/.claude/settings.json` env, pct stays 80, trigger ~200k. Needs a new session. Not verified with `/context`.
- Haiku subagent windows `autoCompactWindow` 110000 -> 120000 in all 9 `agents/*.md` (user choice). Global pct 80 applies (no per-agent pct key found), trigger ~96k: under the Haiku 5.5 100k price tier
  (prompts over 100k cost 5x, cache reads count). Not measured: haiku subagent peak context (re-run `ctx.py`).
- Cache-read price per MTok (pricing page): Sonnet 5 $0.20 -> 5.5 $0.10; Opus 5 $0.50 -> 5.5 $0.20; Fable 5 $1.00 -> 5.2 $0.20. Sonnet 5/Opus 5 already use the newer tokenizer, so no 30% penalty between 5 and 5.5.
  Estimate, 400k session (100 turns, ~4k/turn, 5m writes, 1.5k output/turn, no subagents): Sonnet $6.46 -> $4.48, Opus $16.15 -> $8.96; compacting at ~200k trims Sonnet 5.5 to ~$3.85. Assumed, not measured.
- Memory note `patterns/agent-context-cost.md` autocompact line corrected (was "~350k"). Merged branches `audit-2026-11-18-prompt-fixes`, `pull-sources-skill-agents-skills` deleted locally; remote heads were already auto-deleted (`git fetch --prune` cleared the stale refs; `push --delete` is hook-blocked).

## 2026-11-25
- Sandbox session ran with the full 1M window and never compacted: `CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000` (11-21 fix) had only reached `settings.admin.json`; pct 80 alone triggers ~800k. Added the var to `settings.sandbox.json`, `settings.sandbox.windows.json`, `settings.admin.windows.json`. Needs a new session + config sync. Not verified with `/context`.
- PRs opened without a request: academy session `5e870202` (last 7 days), 6 `gh pr create` calls (transcript lines 4728, 5009, 5443, 5710, 6158, 6633), each right after a subagent hand-back with no user PR request; user objected at line 6642. 3 other calls (academy 3372, grocery-shop 6710, 2292) had a go-ahead. Cause: `rules/git-prs.md` / CLAUDE.md say "'pr'/'squash pr' is the go-ahead" for the squash step only; nothing said opening a PR needs an explicit request. Found by a haiku code-search pass, line numbers unverified by hand.
- Fix: rule line added to `rules/git-prs.md` (no `gh pr create` without the user's own PR request). Not yet mirrored in CLAUDE.md Git/PRs section (cached-prefix rule: edit between sessions).
