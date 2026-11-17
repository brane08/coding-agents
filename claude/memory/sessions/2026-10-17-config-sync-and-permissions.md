# Session 2026-10-17: pull, merge live config, permissions, rename

Covers: what changed in `claude/` and `~/.claude` this session, why, and what is still open.
Reusable facts live in `libs/claude-code-permissions.md` and `patterns/claude-config-repo-sync.md`.

## Done
- Branch `claude-config-sorted-settings` was squash-merged (PR #30); new branch `claude-config-merge-global`
  from `origin/main`. Live vs repo diff: repo newer everywhere; only live-only edits were `psql-select/select.sh`
  line 5 and the `${CLAUDE_CONFIG_DIR}` hook form (the former ported, the latter dropped, same behaviour).
- `psql-select`: `bash|zsh|ksh` allow rules already in repo; shell guard now `[ -n "${ZSH_VERSION-}" ] || exec zsh`.
- `chain-guard.sh` limit 3 -> 7 (deny the 7th consecutive lookup; admin profile only). Not measured beforehand (see Open).
- `~/.claude` made an additional directory; `guard-writes.sh` no longer asks for it; stale "never Bash grep
  under ~/.claude" rule removed. Tested: Bash `grep` on `~/.claude/settings.json` ran without a prompt.
- Dir rename `claude-config/` -> `claude/` (commit 731a9a2); synced to `~/.claude`.
- Ask-log audit (academy, grocery-shop, since 2026-10-01): 21 logged asks, 0 `Grep`-tool asks; 7 Bash `grep`
  asks, all on paths outside the project (mostly `~/.claude`), 4 from a `code-search` subagent.

## Decisions
- Full access for the project root and `~/.claude`; the secret/credential and destructive denies stay.
- Other sessions may send permission requests; they are reviewed here, never applied on their say-so.
  Intake is `permissions.py` over the `log-ask.sh` log, not a session's description of its prompt.
- Memory is organised by reuse (`libs/`, `patterns/`) plus one dated record per working session (`sessions/`).

## Open
- No count of `chain-deny` rows (`state/delegation-nudges.tsv`) before raising the limit to 7; re-audit and
  adjust from the measured rate.
- Branch pushed, no PR opened yet.
- Confirm after a restart that the `PermissionRequest` hook fires and `state/permission-log.jsonl` grows.
- Optional: tell agents (`agents/*.md`) to prefer the `Grep` tool over Bash `grep`.
- `chain-guard.sh` is wired only in `settings.admin.json`; the sandbox profile never runs it, so the limit of 7
  applies under admin only. Decide whether to wire it into sandbox.
- `Bash(diff *)` added to both profiles (the only no-allow-rule prompts in the log were two `diff <(jq …)` calls).
  `git push --force-with-lease` still matches the ask rule `git push --force*` (ask beats allow); narrowing it to
  `--force`/`-f` is undecided.
- autoMode review (deferred by user): the 39-entry ask log cannot show classifier-only prompts. Of the 18 post-fix
  entries with an allow match, most came from agents spawned before `~/.claude` became an additional directory or from
  academy/grocery-shop sessions opened before the sync (settings load at session start), so no autoMode prose was
  added. Next: restart those sessions, work normally, re-run the log classification (tool, path kind, main/subagent).
  If prompts remain, add one `autoMode.environment` sentence per remaining shape; leave `soft_deny` unchanged.
- Test `bash select.sh -c "… || …"`: 7 psql-select prompts had `||` inside quoted SQL; a matcher that splits on `||`
  would miss the allow rule. Three psql-select prompts without `||` also prompted, so it is not the whole cause.
