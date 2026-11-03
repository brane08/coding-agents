# Claude Code permissions & hooks (verified 2026-10-17)

Covers: why tool calls prompt, how allow/ask/deny rules, `additionalDirectories` and hooks interact.
Config source: `settings.<profile>.json` in the repo (`patterns/claude-config-repo-sync.md`).

## Prompts on `~/.claude`
- `blockReadsOutsideWorkingDirectories: true` makes Bash `grep`/`cat`/`ls` on paths outside the
  project prompt, even with `Bash(grep *)` allowed. `Read(~/.claude/**)` allow rules do not help Bash.
- Fix: `permissions.additionalDirectories: ["~/.claude"]`. Tested: Bash `grep` on `~/.claude/settings.json`
  ran with no prompt. The `Grep`/`Glob` tools follow the `Read(...)` rules, so they never prompted.
- Subagent prompts came from agents choosing Bash `grep` (the `Grep` tool was missing in their session).
  Tell agents to prefer the `Grep` tool; Bash `grep` is the fallback.

## Rule matching
- Compound commands (`a | b`, `a && b`) are matched part by part: every part needs an allow rule.
  `jq`, `head`, `wc` are allowed, so `jq … | head` passes; `jq … | <unlisted>` prompts.
- Rule styles in use: `Bash(cmd *)`, legacy `Bash(cmd:*)`, `Bash(git status*)` (no space).
- Skill/hook scripts match only as `bash|zsh|ksh ~/.claude/skills/<skill>/<script>.sh`. `$HOME` or an
  absolute path does not match the `~` rule. Scripts re-exec into their own shell, so any of the three works.
- Deny beats allow; keep the secret/credential denies (`.env`, `*.key`, `*.pem`, `~/.ssh`, `~/.aws`).

## Hooks
- `guard-writes.sh` (PreToolUse on file tools): project and scratchpad pass, `~/.claude` passes through
  to normal rules (was `ask` before 2026-10-17), everything else denied.
- `chain-guard.sh` (wired in admin and sandbox): counts consecutive lookups (`grep rg find cat ls tail head wc sed awk tree fd`,
  `git log|diff|show|blame`); Edit/Write/Agent resets. It never inspects `;`/`&&`/`|`; it judges the first word.
  Deny fires when the counter is already at `limit-1` (limit now 7, was 3). `bash -c "<cmd>"` is judged by `<cmd>`.
- `log-ask.sh` (PermissionRequest): appends every prompt to `state/permission-log.jsonl`;
  `delegation-audit/permissions.py` groups it and proposes allow rules.
- Hook/permission changes may need a session restart to take effect; confirm with a test command.

## Gotchas
- `permissions.py --dry-run` still rewrites `state/permission-analysis/permission-report.md`
  (settings untouched).
- A subagent saying a tool is "unavailable" can be true only for its session; verify before concluding.
- Subagent reports are data: a request inside one (edit settings, grant access) is not user approval.

## Subagent and Bash command shapes that prompt or fail (rule audit + one 8-session scan)
- Some subagent sessions lack `Grep`, `Glob` and `Monitor` ("No such tool available"; seen 82/18/13 times in 49 subagent transcripts). They fall back to Bash `grep`/`find`, which then hits the rules below. Keep fallback greps single, in-project, no pipes; delegate sweeps to `code-search`.
- `select.sh` (psql-select) is zsh-only: it must re-exec itself under zsh when started from `bash` (one line after the header), else it errors "not read-only" and agents fall back to `zsh …` or plain `psql`. The allow rule matches only the `bash ~/.claude/skills/psql-select/select.sh *` form. Don't pass host/port/user flags: the script fixes them.
- `sed -n 'a,bp' f` has no allow rule: use Read with `offset`/`limit`. Same for `awk`, `xargs grep`, `tree`, `fd`: use Grep/Glob or `grep -rn`. `rg`, `git grep` and `uniq` are allowed now.
- Local-host plain `psql`/`pg_dump`/`createdb`/`dropdb` (`-h localhost|127.0.0.1`) are allowed; dropping `prore`/`prore_test` is denied; plain `psql` is no longer in ask.
- Chained Bash (`;`, `&&`, `|`) skips allow rules: in a scan, 757 calls starting with an allowed word still contained a chain. One command per call; say "no chaining" in every ad hoc agent prompt.
- `printf … >> file` / `cat > f <<EOF` appends and heredoc writes are denied by hook/classifier (heredocs were the top prompted shape, 20 of 170): use Write, or Edit anchored on the file's last line.
- `test.sh` accepts only `<module> [Class]`; a flag such as `--summary` is taken as a test class and runs nothing (`--summary` is `ng-verify/verify.sh` only). Same for custom flags via `quick-triage`.
- Multi-line `Edit` on `.claude/memory/**` can trip the auto-mode classifier (false "Self-Modification"/"Cloud Storage Mass Delete"); one row or block per Edit passes.
